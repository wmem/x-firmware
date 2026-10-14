function main(project_root)
    local root = path.absolute(project_root or ".")
    local modules = path.join(root, "addon/modules")
    local api = import("api", {rootdir = modules})
    local fmt = import("format", {rootdir = modules})
    local lz = import("lz4", {rootdir = modules})
    local bs = import("bsdiff", {rootdir = modules})
    local pcall_raw = debug.global("pcall")
    local output = path.join(root, "build/文件 API 空格")
    os.mkdir(output)
    local function file(name) return path.join(output, name) end
    local function save(name, data) io.writefile(file(name), data, {encoding = "binary"}); return file(name) end
    local function read(name) return io.readfile(file(name), {encoding = "binary"}) end
    local reference = path.join(output, "reference")
    local refdir = path.join(root, "tests/reference")
    os.vrunv("cc", {"-O2", "-I" .. refdir, path.join(refdir, "driver.c"), path.join(refdir, "bsdiff.c"),
                    path.join(refdir, "bspatch.c"), "-o", reference})
    local cases = {{"", ""}, {"", "new"}, {"old", ""}, {"a", "b"},
                   {string.rep("abc\0", 1000), string.rep("abc\0", 1001)},
                   {"prefix" .. string.rep("ABC", 1000), string.rep("ABC", 500) .. "change" .. string.rep("ABC", 600)}}
    local random = 3
    local function random_data(size)
        local bytes = {}
        for i = 1, size do random = (random * 16807) % 2147483647; bytes[i] = string.char(random % 256) end
        return table.concat(bytes)
    end
    for n = 1, 20 do
        local old = random_data(n * 131)
        cases[#cases + 1] = {old, old:sub(1, n * 40) .. random_data(n * 13) .. old:sub(n * 60 + 1)}
    end
    for n, pair in ipairs(cases) do
        local oldfile, newfile = save("old.bin", pair[1]), save("new.bin", pair[2])
        local patchfile, packedfile = file("patch.bin"), file("new.lz4")
        api.diff_bsdiff(oldfile, newfile, patchfile)
        assert(bs.patch(pair[1], read("patch.bin"), #pair[2]) == pair[2])
        os.vrunv(reference, {"patch", oldfile, patchfile, file("restored.bin"), tostring(#pair[2])})
        assert(read("restored.bin") == pair[2], "C bspatch: " .. n)
        os.vrunv(reference, {"diff", oldfile, newfile, file("reference.patch")})
        assert(bs.patch(pair[1], read("reference.patch"), #pair[2]) == pair[2], "C bsdiff: " .. n)
        api.compress_lz4(newfile, packedfile)
        assert(lz.decompress(read("new.lz4"), #pair[2]) == pair[2])
        os.vrunv("uv", {"run", "--no-project", "--offline", "python", path.join(root, "tests/lz4_reference.py"),
                       newfile, packedfile})
        assert(lz.decompress(read("new.lz4.reference"), #pair[2]) == pair[2], "C LZ4: " .. n)
    end
    local function app(name, version, data)
        local addr = 0x08004000
        local bytes = fmt.u32(0x20020000) .. fmt.u32(addr + 9) .. string.rep("\255", 1016)
                      .. fmt.u32(fmt.layout("run").magic) .. string.rep("\0", 124) .. data
        local raw = save(name .. ".raw", bytes)
        api.fill_run_header(raw, file(name), {version = version, addr = addr, identifier = "APPTEST",
                                             platform = "KY3133_B00;VE_TEST"}, {header_capacity = 128})
        local filled = read(name)
        assert(#filled == #bytes and filled:sub(1, 1024) == bytes:sub(1, 1024)
               and filled:sub(1153) == bytes:sub(1153))
        return file(name)
    end
    local oldfile = app("v1.bin", 1, random_data(8000))
    local newfile = app("v2.bin", 2, read("v1.bin"):sub(1153, 4000) .. "change" .. read("v1.bin"):sub(4200))
    for _, compression in ipairs({"none", "lz4"}) do
        api.make_upgrade(newfile, file("up-" .. compression), {}, {compression = compression})
        assert(api.inspect(file("up-" .. compression)).restored_crc_valid)
        api.make_diff(oldfile, newfile, file("diff-" .. compression), {}, {compression = compression})
        local inspected = api.inspect(file("diff-" .. compression))
        local image = read("diff-" .. compression)
        if compression == "lz4" then
            image = lz.decompress(image:sub(inspected.header.magic.size + 1), inspected.header.src_size)
        end
        local header = fmt.decode_header(image)
        assert(bs.patch(read("v1.bin"), image:sub(header.magic.size + 1), header.dst_size) == read("v2.bin"))
    end
    api.write_product(file("product.bin"), {platform = "VE_TEST", serial = "123"})
    assert(api.decode_product(read("product.bin")).platform == "VE_TEST")
    local protected = save("protected.bin", "keep")
    assert(not pcall_raw(function() api.fill_run_header(newfile, protected, {version = 3, addr = 0x08004000,
        identifier = "TOO_LONG_IDENTIFIER", platform = "VE_TEST"}, {header_capacity = 128}) end))
    assert(read("protected.bin") == "keep", "失败改变了已有输出")
    api.make_upgrade(newfile, protected)
    assert(api.inspect(protected).kind == "upgrade", "已有输出覆盖失败")
    assert(not pcall_raw(function() api.make_upgrade(newfile, file("empty"), {platform = ""}) end))
    local up = read("up-none")
    local header = fmt.decode_header(up)
    api.add_header(save("payload.bin", up:sub(header.magic.size + 1)), file("added.bin"),
        {kind = "upgrade", addr = header.addr, version = header.version, identifier = header.identifier,
         platform = header.platform, dat_type = 0})
    assert(read("added.bin") == up)
    local start = os.mclock()
    local large_old = string.rep(random_data(1024), 256)
    local large_new = large_old:sub(1, 100000) .. random_data(1000) .. large_old:sub(101001) .. "TAIL"
    local patchdata = bs.diff(large_old, large_new)
    assert(bs.patch(large_old, patchdata, #large_new) == large_new)
    local message = string.format("PASS: %d 组 Lua/C 双向算法互通，三类镜像、中文空格路径、原位加头和失败保护；256 KiB bsdiff %.3fs，补丁 %dB，LZ4 后 %dB。",
                                  #cases, (os.mclock() - start) / 1000, #patchdata, #lz.compress(patchdata))
    io.writefile(file("result.txt"), message .. "\n")
    print(message)
end
