-- 标准 LZ4 raw block；大小由固件头提供，不添加 Frame 或私有块头。
local function extension(parts, value)
    while value >= 255 do parts[#parts + 1] = "\255"; value = value - 255 end
    parts[#parts + 1] = string.char(value)
end

local function sequence(parts, literals, distance, length)
    local ll = #literals
    local ml = length and length - 4 or 0
    parts[#parts + 1] = string.char(math.min(ll, 15) * 16 + math.min(ml, 15))
    if ll >= 15 then extension(parts, ll - 15) end
    parts[#parts + 1] = literals
    if distance then
        parts[#parts + 1] = string.char(distance % 256, math.floor(distance / 256))
        if ml >= 15 then extension(parts, ml - 15) end
    end
end

function compress(data)
    assert(type(data) == "string", "LZ4 输入必须为字节字符串")
    local parts, dictionary = {}, {}
    local anchor, cursor, size = 1, 1, #data
    -- 遵循末尾 5 字节为 literal、最后一次 match 至少距末尾 12 字节的限制。
    while cursor <= size - 11 do
        local key = data:sub(cursor, cursor + 3)
        local previous = dictionary[key]
        dictionary[key] = cursor
        if previous and cursor - previous <= 65535 then
            local count = 4
            while cursor + count <= size - 5 and data:byte(previous + count) == data:byte(cursor + count) do
                count = count + 1
            end
            sequence(parts, data:sub(anchor, cursor - 1), cursor - previous, count)
            for index = cursor + 1, cursor + count - 1 do
                dictionary[data:sub(index, index + 3)] = index
            end
            cursor = cursor + count
            anchor = cursor
        else
            cursor = cursor + 1
        end
    end
    sequence(parts, data:sub(anchor))
    return table.concat(parts)
end

function decompress(data, size)
    assert(type(data) == "string" and #data >= 1, "LZ4 raw block 至少包含一个 token")
    assert(type(size) == "number" and size >= 0 and size % 1 == 0, "LZ4 输出长度无效")
    local output, cursor = {}, 1
    local function byte()
        assert(cursor <= #data, "LZ4 数据截断")
        local value = data:byte(cursor); cursor = cursor + 1; return value
    end
    local function length(value)
        if value == 15 then
            local extra
            repeat extra = byte(); value = value + extra until extra ~= 255
        end
        assert(value <= size, "LZ4 长度超限")
        return value
    end
    while cursor <= #data do
        local token = byte()
        local literals = length(math.floor(token / 16))
        assert(cursor + literals - 1 <= #data and #output + literals <= size, "LZ4 literal 越界")
        for _ = 1, literals do output[#output + 1] = string.char(byte()) end
        if cursor > #data then break end
        local distance = byte() + byte() * 256
        assert(distance > 0 and distance <= #output, "LZ4 offset 无效")
        local count = length(token % 16) + 4
        assert(#output + count <= size, "LZ4 match 越界")
        for _ = 1, count do output[#output + 1] = output[#output - distance + 1] end
    end
    assert(cursor == #data + 1 and #output == size, "LZ4 输出长度不一致")
    return table.concat(output)
end
