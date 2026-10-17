-- 验证压缩器距离承诺、type_arg 以及独立 liblz4 互通。
function main(project_root)
    local root = path.absolute(project_root or ".")
    local api = import("api", {rootdir = path.join(root, "addon/modules")})
    local lz4 = import("lz4", {rootdir = path.join(root, "addon/modules")})
    local fmt = import("format", {rootdir = path.join(root, "addon/modules")})
    local crc = import("crc32", {rootdir = path.join(root, "addon/modules")})
    local raw_pcall = debug.global("pcall")
    local output = path.join(root, "build/max-distance")
    os.mkdir(output)
    local seed, bytes = 7, {}
    for i = 1, 20000 do
        seed = seed * 16807 % 2147483647
        bytes[i] = string.char(seed % 256)
    end
    local sample = table.concat(bytes)
    local input = path.join(output, "app.bin")
    io.writefile(input, fmt.u32(0x20020000) .. fmt.u32(0x08004009) .. string.rep("\255", 1016)
        .. fmt.u32(fmt.layout("run").magic) .. string.rep("\0", 124) .. sample .. sample .. sample,
        {encoding = "binary"})
    api.fill_run_header(input, input, {addr = 0x08004000, version = 1, identifier = "DISTANCE",
        platform = "TEST"}, {header_capacity = 128})
    local original = io.readfile(input, {encoding = "binary"})
    local results = {}
    for _, limit in ipairs({0, 1, 256, 1000, 16384, 32768, 65535}) do
        local filename = path.join(output, "upgrade-" .. limit .. ".bin")
        api.make_upgrade(input, filename, nil, {compression = "lz4", lz4_max_distance = limit})
        local info = api.inspect(filename)
        assert(info.header.type_arg == limit and info.restored_crc_valid)
        local payload = io.readfile(filename, {encoding = "binary"}):sub(info.header.magic.size + 1)
        assert(lz4.decompress(payload, #original, limit) == original)
        local packed = path.join(output, "raw-" .. limit .. ".lz4")
        io.writefile(packed, payload, {encoding = "binary"})
        os.vrunv("uv", {"run", "--no-project", "--offline", "python",
            path.join(root, "tests/lz4_reference.py"), input, packed})
        results[#results + 1] = {max_distance = limit, packed_bytes = #payload}
    end
    for _, value in ipairs({-1, 1.5, 65536, "16384"}) do
        assert(not raw_pcall(function() lz4.compress(sample, value) end))
    end
    -- 合法 CRC 但声明为零距离，工具必须发现内容不满足声明。
    local filename = path.join(output, "upgrade-65535.bin")
    local packet = io.readfile(filename, {encoding = "binary"})
    local head = fmt.decode_header(packet)
    head.type_arg = 0
    local forged = path.join(output, "under-declared.bin")
    io.writefile(forged, fmt.encode_header("upgrade", head) .. packet:sub(head.magic.size + 1),
        {encoding = "binary"})
    assert(not raw_pcall(function() api.inspect(forged) end))
    api.make_upgrade(input, path.join(output, "plain.bin"))
    assert(api.inspect(path.join(output, "plain.bin")).header.type_arg == 0)
    import("core.base.json").savefile(path.join(output, "result.json"),
        {status = "PASS", cases = results, malformed_rejected = 5}, {indent = true})
    print("PASS: 7 种距离上限、包头参数、独立 liblz4 互通及低报声明拒绝")
end
