import("format", {rootdir = os.scriptdir()})
import("crc32", {rootdir = os.scriptdir()})
import("lz4", {rootdir = os.scriptdir()})
import("bsdiff", {rootdir = os.scriptdir()})
local headers = path.join(os.scriptdir(), "include")

function include_dir()
    return headers
end

function encode_header(kind, info)
    return format.encode_header(kind, info)
end

function decode_header(data, offset)
    return format.decode_header(data, offset)
end

function encode_product(values)
    return format.encode_product(values)
end

function decode_product(data, offset)
    return format.decode_product(data, offset)
end

local function read_file(filename)
    assert(type(filename) == "string" and #filename > 0, "请传入文件名")
    return assert(io.readfile(filename, {encoding = "binary"}), "不能读取文件：" .. filename)
end

local function write_file(filename, data)
    assert(type(filename) == "string" and #filename > 0, "请传入输出文件名")
    local directory = path.directory(path.absolute(filename))
    os.mkdir(directory)
    local temporary = path.join(directory, ".x-firmware-" .. path.filename(os.tmpfile()))
    try {
        function()
            io.writefile(temporary, data, {encoding = "binary"})
            os.mv(temporary, filename)
        end,
        finally {function() os.tryrm(temporary) end}
    }
end

local function platform_info(run, info)
    info = info or {}
    local identifier = info.identifier or run.identifier
    local platform = info.platform or run.platform
    assert(type(platform) == "string" and #platform > 0 and not platform:find("\0", 1, true),
           "支持平台列表不能为空")
    assert(platform:sub(1, 1) ~= ";" and platform:sub(-1) ~= ";" and not platform:find(";;", 1, true),
           "支持平台列表有空项")
    assert(type(identifier) == "string" and #identifier <= 15,
           "identifier 最多为 15 字节")
    return identifier, platform
end

local function locate_run(data, options, filled)
    options = options or {}
    local candidates = {}
    if options.header_offset ~= nil then
        local offset = options.header_offset
        assert(type(offset) == "number" and offset >= 0 and offset % 1024 == 0,
               "运行头偏移必须 1 KiB 对齐")
        candidates[1] = offset + 1
        assert(format.read_u32(data, offset + 1) == format.layout("run").magic, "指定位置不是运行头")
    else
        for offset = 0, #data - 44, 1024 do
            if format.read_u32(data, offset + 1) == format.layout("run").magic then
                candidates[#candidates + 1] = offset + 1
            end
        end
    end
    assert(#candidates == 1, "运行头候选数量必须为 1，实际：" .. #candidates)
    local offset = candidates[1]
    assert(offset >= 9, "运行头覆盖了向量表起始")
    if not filled then return offset end
    local run = format.decode_header(data, offset)
    assert(run.size == #data and run.addr % 1024 == 0 and run.addr + #data <= 4294967296,
           "运行镜像长度或地址错误")
    local reset = format.read_u32(data, 5)
    assert(reset % 2 == 1 and reset - 1 >= run.addr and reset - 1 < run.addr + run.size,
           "APP 复位向量不在运行镜像内")
    return offset, run
end

local function metadata(filename, bytes, header, offset)
    return {path = path.absolute(filename), size = #bytes, header = header,
            header_offset = offset and offset - 1 or 0}
end

function fill_run_header(input, output, info, options)
    assert(type(info) == "table", "请传入固件信息")
    options = options or {}
    local data = read_file(input)
    local offset = locate_run(data, options, false)
    local capacity = options.header_capacity
    assert(type(capacity) == "number" and capacity >= 45 and capacity % 1 == 0
           and offset + capacity - 1 <= #data, "必须显式提供有效的运行头预留容量 header_capacity")
    local identifier, platform = platform_info({}, info)
    local bytes = format.encode_header("run", {version = info.version, addr = info.addr, size = #data,
                                               identifier = identifier, platform = platform})
    assert(#bytes <= capacity, "运行头超出源码预留容量")
    local result = data:sub(1, offset - 1) .. bytes .. string.rep("\0", capacity - #bytes)
                   .. data:sub(offset + capacity)
    local _, run = locate_run(result, {header_offset = offset - 1}, true)
    write_file(output, result)
    return metadata(output, result, run, offset)
end

function compress_lz4(input, output, info, options)
    local data = read_file(input)
    local compressed = lz4.compress(data)
    write_file(output, compressed)
    return {path = path.absolute(output), size = #compressed, src_size = #data,
            src_crc = crc32.sum(data), dat_crc = crc32.sum(compressed), backend = "lua"}
end

function diff_bsdiff(oldfile, newfile, output, info, options)
    local old, new = read_file(oldfile), read_file(newfile)
    local patchdata = bsdiff.diff(old, new)
    write_file(output, patchdata)
    return {path = path.absolute(output), size = #patchdata, src_size = #old,
            src_crc = crc32.sum(old), dst_size = #new, dst_crc = crc32.sum(new), backend = "lua"}
end

function add_header(input, output, info, options)
    assert(type(info) == "table", "请传入头部信息")
    local kind = info.kind
    assert(kind == "upgrade" or kind == "diff" or kind == "encrypt",
           "add_header 只支持升级/差分/外层头；APP 使用 fill_run_header")
    local data = read_file(input)
    local fields = table.clone(info)
    fields.dat_size, fields.dat_crc = #data, crc32.sum(data)
    if kind == "upgrade" and (fields.dat_type or 0) == 0 then
        fields.size, fields.crc, fields.dat_type = #data, crc32.sum(data), 0
    end
    if kind == "encrypt" then fields.dat_crypto = fields.dat_crypto or 0 end
    local bytes = format.encode_header(kind, fields) .. data
    write_file(output, bytes)
    return metadata(output, bytes, format.decode_header(bytes))
end

function make_upgrade(input, output, info, options)
    options = options or {}
    local data = read_file(input)
    local _, run = locate_run(data, options, true)
    local identifier, platform = platform_info(run, info)
    local mode = options.compression or "none"
    assert(mode == "none" or mode == "lz4", "compression 只支持 none/lz4")
    local payload = mode == "lz4" and lz4.compress(data) or data
    local head = {addr = run.addr, size = #data, crc = crc32.sum(data), version = run.version,
                  dat_size = #payload, dat_crc = crc32.sum(payload), dat_type = mode == "lz4" and 1 or 0,
                  identifier = identifier, platform = platform}
    local bytes = format.encode_header("upgrade", head) .. payload
    write_file(output, bytes)
    return metadata(output, bytes, format.decode_header(bytes))
end

function make_diff(oldfile, newfile, output, info, options)
    options = options or {}
    local old, new = read_file(oldfile), read_file(newfile)
    local _, source = locate_run(old, options.old or {}, true)
    local _, target = locate_run(new, options.new or {}, true)
    local identifier, platform = platform_info(target, info)
    local patchdata = bsdiff.diff(old, new)
    local head = {src_addr = source.addr, src_size = #old, src_crc = crc32.sum(old), src_version = source.version,
                  dst_addr = target.addr, dst_size = #new, dst_crc = crc32.sum(new), dst_version = target.version,
                  dat_size = #patchdata, dat_crc = crc32.sum(patchdata), identifier = identifier, platform = platform}
    local inner = format.encode_header("diff", head) .. patchdata
    local mode = options.compression or "lz4"
    assert(mode == "none" or mode == "lz4", "compression 只支持 none/lz4")
    local bytes = inner
    if mode == "lz4" then
        local packed = lz4.compress(inner)
        bytes = format.encode_header("encrypt", {src_size = #inner, dat_size = #packed,
            dat_crc = crc32.sum(packed), dat_crypto = 0}) .. packed
    end
    write_file(output, bytes)
    local result = metadata(output, bytes, format.decode_header(bytes))
    result.inner_header, result.decompressed_size = format.decode_header(inner), #inner
    return result
end

local function inspect_bytes(data)
    local flag = format.read_u32(data, 1)
    if flag ~= format.layout("upgrade").magic and flag ~= format.layout("diff").magic
       and flag ~= format.layout("encrypt").magic then
        local offset, run = locate_run(data, {}, true)
        return {kind = "run", header = run, header_offset = offset - 1, size = #data}
    end
    local header = format.decode_header(data)
    local payload = data:sub(header.magic.size + 1)
    assert(#payload == header.dat_size and crc32.sum(payload) == header.dat_crc, "载荷长度或 CRC 错误")
    local result = {kind = header.kind, header = header, size = #data, payload_crc_valid = true}
    if header.kind == "encrypt" then
        assert(header.dat_crypto == 0, "不支持外层数据算法")
        result.inner = inspect_bytes(lz4.decompress(payload, header.src_size))
        assert(result.inner.kind == "diff" or result.inner.kind == "upgrade", "外层内容类型错误")
    elseif header.kind == "upgrade" then
        assert(header.dat_type == 0 or header.dat_type == 1, "不支持升级数据算法")
        local restored = header.dat_type == 1 and lz4.decompress(payload, header.size) or payload
        assert(#restored == header.size and crc32.sum(restored) == header.crc, "完整固件 CRC 错误")
        local _, run = locate_run(restored, {}, true)
        assert(run.addr == header.addr and run.version == header.version, "升级头与 APP 信息不一致")
        result.restored_crc_valid = true
    end
    return result
end

function inspect(input, options)
    local result = inspect_bytes(read_file(input))
    result.path = path.absolute(input)
    return result
end

function write_product(output, values, options)
    local bytes = format.encode_product(values)
    write_file(output, bytes)
    return {path = path.absolute(output), size = #bytes, values = format.decode_product(bytes)}
end

-- 规则及命令的共同入口；路径基准由调用方明确提供，文件 API 本身不改变 cwd。
function execute(operation, config, base_dir)
    assert(type(config) == "table" and type(base_dir) == "string", "请提供配置和路径基准")
    local function filename(key)
        assert(type(config[key]) == "string" and #config[key] > 0, "缺少路径：" .. key)
        return path.absolute(config[key], base_dir)
    end
    if operation == "app" then return fill_run_header(filename("input"), filename("output"), config.info, config.options)
    elseif operation == "upgrade" then return make_upgrade(filename("input"), filename("output"), config.info, config.options)
    elseif operation == "diff" then return make_diff(filename("old"), filename("new"), filename("output"), config.info, config.options)
    elseif operation == "inspect" then return inspect(filename("input"), config.options)
    elseif operation == "product" then return write_product(filename("output"), config.values, config.options)
    else raise("未知操作：" .. tostring(operation)) end
end
