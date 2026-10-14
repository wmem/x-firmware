import("format", {rootdir = os.scriptdir()})
local headers = path.absolute("../include", os.scriptdir())

-- 第一阶段公开协议入口；文件打包 API 在后续实现后再暴露。
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
