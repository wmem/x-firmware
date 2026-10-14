import("core.base.bit")

local table_crc = {}
for byte = 0, 255 do
    local value = byte
    for _ = 1, 8 do
        if bit.band(value, 1) ~= 0 then
            value = bit.bxor(bit.rshift(value, 1), 0xedb88320)
        else
            value = bit.rshift(value, 1)
        end
    end
    table_crc[byte] = value
end

-- CRC-32/ISO-HDLC，与旧 MCU_boot 一致；seed 为未做最终异或的流式状态。
function update(data, seed)
    assert(type(data) == "string", "CRC 输入必须为字节字符串")
    local value = seed or 0xffffffff
    for index = 1, #data do
        value = bit.bxor(bit.rshift(value, 8),
                         table_crc[bit.band(bit.bxor(value, data:byte(index)), 255)])
    end
    return value
end

function finish(state)
    return bit.bxor(state, 0xffffffff) % 4294967296
end

function sum(data)
    return finish(update(data))
end
