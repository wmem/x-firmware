function main(project_root)
    local raw_pcall = debug.global("pcall")
    local root = path.absolute(project_root or ".")
    local modules = path.join(root, "addon/modules")
    local fmt = import("format", {rootdir = modules})
    local crc = import("crc32", {rootdir = modules})
    local api = import("api", {rootdir = modules})
    local output = path.join(root, "build/protocol")
    os.mkdir(output)
    assert(crc.sum("123456789") == 0xcbf43926 and crc.sum("") == 0)
    assert(crc.finish(crc.update("56789", crc.update("1234"))) == 0xcbf43926)
    local samples = {
        run = {version = 7, addr = 0x08004000, size = 98304},
        upgrade = {addr = 0x08004000, size = 98304, crc = 0x11223344, version = 7,
                   dat_size = 65432, dat_crc = 0xdeadbeef, dat_type = 1, type_arg = 16384},
        diff = {src_addr = 0x08004000, src_size = 80000, src_crc = 0x10203040, src_version = 6,
                dst_addr = 0x08004000, dst_size = 98304, dst_crc = 0x11223344, dst_version = 7,
                dat_size = 50123, dat_crc = 0xdeadbeef},
        encrypt = {src_size = 50195, dat_size = 23456, dat_crc = 0xaabbccdd, dat_crypto = 0}
    }
    local count = 0
    local function rejects(callback)
        assert(not raw_pcall(callback), "无效输入没有被拒绝")
        count = count + 1
    end
    for kind, info in pairs(samples) do
        if kind ~= "encrypt" then info.identifier, info.platform = "sample", "KY3133_B00;TEST" end
        local bytes = api.encode_header(kind, info)
        assert(#bytes == fmt.layout(kind).fixed_size + (info.platform and #info.platform + 1 or 0))
        io.writefile(path.join(output, "lua-" .. kind .. ".bin"), bytes, {encoding = "binary"})
        local actual = api.decode_header(bytes)
        for key, value in pairs(info) do assert(actual[key] == value, kind .. ":" .. key) end
        rejects(function() api.decode_header(bytes:sub(1, -2)) end)
        rejects(function() api.decode_header(bytes:sub(1, 12) .. "X" .. bytes:sub(14)) end)
        assert(api.decode_header("prefix" .. bytes .. "suffix", 7).kind == kind)
    end
    local product = api.encode_product({platform = "KY3133_B00", name = "test"})
    io.writefile(path.join(output, "lua-product.bin"), product, {encoding = "binary"})
    assert(api.decode_product(product).platform == "KY3133_B00")
    rejects(function() api.decode_product(product:sub(1, -2)) end)
    rejects(function() api.decode_product(product:sub(1, 12) .. "X" .. product:sub(14)) end)
    rejects(function() fmt.u32(-1) end)
    rejects(function() fmt.u32(4294967296) end)
    rejects(function() fmt.u32(1.5) end)
    rejects(function() api.encode_product({["bad=key"] = "value"}) end)
    rejects(function() api.encode_product({key = "bad\0value"}) end)
    local too_long = table.clone(samples.run)
    too_long.identifier = "1234567890123456"
    rejects(function() api.encode_header("run", too_long) end)
    -- 主机 C 参考实现生成同样的镜像，确保字段布局不是 Lua 自测闭环。
    local executable = path.join(output, "protocol-reference" .. (os.host() == "windows" and ".exe" or ""))
    os.vrunv("cc", {"-std=c11", "-Wall", "-Wextra", "-Werror", "-I" .. api.include_dir(),
                     path.join(root, "tests/protocol_reference.c"), "-o", executable})
    os.vrunv(executable, {output})
    for kind, _ in pairs(samples) do
        local from_c = io.readfile(path.join(output, "c-" .. kind .. ".bin"), {encoding = "binary"})
        assert(api.decode_header(from_c).kind == kind)
    end
    assert(api.decode_product(io.readfile(path.join(output, "c-product.bin"), {encoding = "binary"})).name == "test")
    os.vrunv("arm-none-eabi-gcc", {"-std=c11", "-Wall", "-Wextra", "-Werror", "-mcpu=cortex-m4",
        "-mthumb", "-I" .. api.include_dir(), "-c", path.join(root, "tests/protocol_reference.c"),
        "-o", path.join(output, "protocol-arm.o")})
    local message = string.format("PASS: C/Lua 五种格式互通、CRC 流式及 %d 个错误输入、ARM 布局编译。", count)
    io.writefile(path.join(output, "result.txt"), message .. "\n")
    print(message)
end
