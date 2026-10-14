import("crc32", {rootdir = os.scriptdir()})

-- 字段顺序只描述线格式；C 定义由 addon/include/x_firmware 提供并互通验证。
local layouts = {
    run = {magic = 0x464d524e, fields = {"version", "addr", "size"}, platform = true},
    upgrade = {magic = 0x464d5550,
        fields = {"addr", "size", "crc", "version", "dat_size", "dat_crc", "dat_type"}, platform = true},
    diff = {magic = 0x464d4446,
        fields = {"src_addr", "src_size", "src_crc", "src_version", "dst_addr", "dst_size",
                  "dst_crc", "dst_version", "dat_size", "dat_crc"}, platform = true},
    encrypt = {magic = 0x464d4554, fields = {"src_size", "dat_size", "dat_crc", "dat_crypto"}}
}

function u32(value)
    assert(type(value) == "number" and value >= 0 and value <= 0xffffffff and value % 1 == 0,
           "字段必须为 uint32")
    return string.char(value % 256, math.floor(value / 256) % 256,
                       math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end

function read_u32(data, offset)
    assert(type(data) == "string" and type(offset) == "number" and offset >= 1
           and offset % 1 == 0 and offset + 3 <= #data, "uint32 数据截断或偏移无效")
    local a, b, c, d = data:byte(offset, offset + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function cstring(value, field)
    assert(type(value) == "string" and not value:find("\0", 1, true), field .. " 不能包含 NUL")
    return value .. "\0"
end

function layout(kind)
    local desc = assert(layouts[kind], "未知固件类型：" .. tostring(kind))
    return {magic = desc.magic, fixed_size = 12 + #desc.fields * 4 + (desc.platform and 20 or 0)}
end

function encode_header(kind, info)
    assert(type(info) == "table", "固件信息必须为 table")
    local desc = assert(layouts[kind], "未知固件类型")
    local parts = {}
    for _, field in ipairs(desc.fields) do
        parts[#parts + 1] = u32(assert(info[field], "缺少字段：" .. field))
    end
    if desc.platform then
        local identifier = cstring(info.identifier, "identifier")
        assert(#identifier <= 16, "identifier 最多 15 字节")
        parts[#parts + 1] = identifier .. string.rep("\0", 16 - #identifier)
        local platform = cstring(info.platform, "platform")
        parts[#parts + 1] = u32(#platform)
        parts[#parts + 1] = platform
    end
    local body = table.concat(parts)
    return u32(desc.magic) .. u32(crc32.sum(body)) .. u32(12 + #body) .. body
end

function decode_header(data, offset)
    offset = offset or 1
    local flag = read_u32(data, offset)
    local kind, desc
    for name, value in pairs(layouts) do
        if value.magic == flag then kind, desc = name, value; break end
    end
    assert(desc, "未知固件 magic")
    local size = read_u32(data, offset + 8)
    local fixed = layout(kind).fixed_size
    assert(size >= fixed and size <= #data - offset + 1, "固件头长度截断或过小")
    local body = data:sub(offset + 12, offset + size - 1)
    assert(crc32.sum(body) == read_u32(data, offset + 4), "固件头 CRC 错误")
    local result = {kind = kind, magic = {flag = flag, size = size, crc32 = read_u32(data, offset + 4)}}
    local cursor = offset + 12
    for _, field in ipairs(desc.fields) do
        result[field] = read_u32(data, cursor)
        cursor = cursor + 4
    end
    if desc.platform then
        local identifier = data:sub(cursor, cursor + 15)
        local term = identifier:find("\0", 1, true)
        assert(term, "identifier 未以 NUL 结束")
        result.identifier = identifier:sub(1, term - 1)
        local count = read_u32(data, cursor + 16)
        assert(count >= 1 and size == fixed + count, "平台长度和头部长度不一致")
        local platform = data:sub(cursor + 20, offset + size - 1)
        assert(platform:sub(-1) == "\0" and not platform:sub(1, -2):find("\0", 1, true),
               "平台字符串的 NUL 无效")
        result.platform = platform:sub(1, -2)
        result.platform_len = count
    else
        assert(size == fixed, "外层头有多余数据")
    end
    return result
end

function encode_product(values)
    assert(type(values) == "table", "产品信息必须为 table")
    local keys = {}
    for key, value in pairs(values) do
        assert(type(key) == "string" and #key > 0 and not key:find("[=\0]"), "产品 key 无效")
        assert(type(value) == "string" and not value:find("\0", 1, true), "产品 value 无效")
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. values[key] .. "\0" end
    local data = table.concat(parts)
    return u32(0x50524454) .. u32(crc32.sum(data)) .. u32(#data) .. data
end

function decode_product(data, offset)
    offset = offset or 1
    assert(read_u32(data, offset) == 0x50524454, "产品 magic 错误")
    local size = read_u32(data, offset + 8)
    assert(size <= #data - offset - 11, "产品数据截断")
    local values = data:sub(offset + 12, offset + 11 + size)
    assert(crc32.sum(values) == read_u32(data, offset + 4), "产品 CRC 错误")
    local result, cursor = {}, 1
    while cursor <= #values do
        local last = assert(values:find("\0", cursor, true), "产品键值未以 NUL 结束")
        local key, value = values:sub(cursor, last - 1):match("^([^=]+)=(.*)$")
        assert(key and result[key] == nil, "产品键值无效或重复")
        result[key] = value
        cursor = last + 1
    end
    return result
end
