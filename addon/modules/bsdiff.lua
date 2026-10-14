-- bsdiff 匹配评分及前后重叠处理移植自 Colin Percival / Matthew Endsley。
-- 许可证见 modules/licenses/bsdiff.txt；后缀数组改为纯 Lua 倍增和计数排序。
-- 输出是未压缩的交错 control/diff/extra，不添加 BSDIFF40/43 文件头。

function offtout(value)
    assert(type(value) == "number" and value % 1 == 0 and math.abs(value) < 9007199254740992,
           "bsdiff offset 超出精确整数范围")
    local parts, absolute = {}, math.abs(value)
    for index = 1, 8 do
        local byte = absolute % 256
        absolute = math.floor(absolute / 256)
        if index == 8 and value < 0 then byte = byte + 128 end
        parts[index] = string.char(byte)
    end
    return table.concat(parts)
end

function offtin(data, offset)
    assert(offset >= 1 and offset + 7 <= #data, "bsdiff control 截断")
    local value = data:byte(offset + 7) % 128
    for index = 6, 0, -1 do value = value * 256 + data:byte(offset + index) end
    assert(value < 9007199254740992, "bsdiff offset 超出精确整数范围")
    return data:byte(offset + 7) >= 128 and -value or value
end

local function suffix_array(data)
    local n, sa, rank = #data, {}, {}
    for index = 0, n do sa[index + 1] = index; rank[index] = index == n and 0 or data:byte(index + 1) + 1 end
    local step, maxrank = 1, 256
    local function sort_by(input, shift)
        local counts, output, next_index = {}, {}, 1
        for key = 0, maxrank do counts[key] = 0 end
        for _, pos in ipairs(input) do local key = rank[pos + shift] or 0; counts[key] = counts[key] + 1 end
        for key = 0, maxrank do local count = counts[key]; counts[key] = next_index; next_index = next_index + count end
        for _, pos in ipairs(input) do
            local key = rank[pos + shift] or 0
            output[counts[key]] = pos; counts[key] = counts[key] + 1
        end
        return output
    end
    while n > 0 do
        sa = sort_by(sort_by(sa, step), 0)
        local next_rank, group = {}, 0
        next_rank[sa[1]] = 0
        for index = 2, #sa do
            local a, b = sa[index - 1], sa[index]
            if rank[a] ~= rank[b] or (rank[a + step] or 0) ~= (rank[b + step] or 0) then group = group + 1 end
            next_rank[b] = group
        end
        rank, maxrank = next_rank, group
        if group == n then break end
        step = step * 2
    end
    return sa
end

local function search(sa, old, new, start)
    local low, high = 1, #sa
    local function common(pos)
        local count, limit = 0, math.min(#old - pos, #new - start)
        while count < limit and old:byte(pos + count + 1) == new:byte(start + count + 1) do count = count + 1 end
        return count, limit
    end
    while high - low >= 2 do
        local middle = math.floor((low + high) / 2)
        local count, limit = common(sa[middle])
        if count < limit and old:byte(sa[middle] + count + 1) < new:byte(start + count + 1) then
            low = middle
        else high = middle end
    end
    local a, b = common(sa[low]), common(sa[high])
    if a > b then return a, sa[low] end
    return b, sa[high]
end

function diff(old, new)
    assert(type(old) == "string" and type(new) == "string", "bsdiff 输入必须为字节字符串")
    local sa = suffix_array(old)
    local parts = {}
    local scan, length, pos, lastscan, lastpos, lastoffset = 0, 0, 0, 0, 0, 0
    local function same(a, b)
        return a >= 0 and a < #old and b >= 0 and b < #new and old:byte(a + 1) == new:byte(b + 1)
    end
    while scan < #new do
        local score = 0
        scan = scan + length
        local scsc = scan
        while scan < #new do
            length, pos = search(sa, old, new, scan)
            while scsc < scan + length do
                if same(scsc + lastoffset, scsc) then score = score + 1 end
                scsc = scsc + 1
            end
            if (length == score and length ~= 0) or length > score + 8 then break end
            if same(scan + lastoffset, scan) then score = score - 1 end
            scan = scan + 1
        end
        if length ~= score or scan == #new then
            local s, sf, lenf, i = 0, 0, 0, 0
            while lastscan + i < scan and lastpos + i < #old do
                if same(lastpos + i, lastscan + i) then s = s + 1 end
                i = i + 1
                if s * 2 - i > sf * 2 - lenf then sf, lenf = s, i end
            end
            local lenb, sb = 0, 0
            if scan < #new then
                s, i = 0, 1
                while scan >= lastscan + i and pos >= i do
                    if same(pos - i, scan - i) then s = s + 1 end
                    if s * 2 - i > sb * 2 - lenb then sb, lenb = s, i end
                    i = i + 1
                end
            end
            if lastscan + lenf > scan - lenb then
                local overlap = lastscan + lenf - scan + lenb
                local best, lens = 0, 0
                s = 0
                for j = 0, overlap - 1 do
                    if same(lastpos + lenf - overlap + j, lastscan + lenf - overlap + j) then s = s + 1 end
                    if same(pos - lenb + j, scan - lenb + j) then s = s - 1 end
                    if s > best then best, lens = s, j + 1 end
                end
                lenf, lenb = lenf + lens - overlap, lenb - lens
            end
            local extra = scan - lenb - lastscan - lenf
            parts[#parts + 1] = offtout(lenf) .. offtout(extra) .. offtout(pos - lenb - lastpos - lenf)
            local bytes = {}
            for j = 0, lenf - 1 do
                bytes[#bytes + 1] = string.char((new:byte(lastscan + j + 1) - (old:byte(lastpos + j + 1) or 0)) % 256)
            end
            parts[#parts + 1] = table.concat(bytes)
            parts[#parts + 1] = new:sub(lastscan + lenf + 1, scan - lenb)
            lastscan, lastpos, lastoffset = scan - lenb, pos - lenb, pos - scan
        end
    end
    return table.concat(parts)
end

function patch(old, patchdata, size)
    local output, cursor, oldpos = {}, 1, 0
    local function take(count)
        assert(count >= 0 and count % 1 == 0 and cursor + count - 1 <= #patchdata, "bsdiff 数据截断")
        local result = patchdata:sub(cursor, cursor + count - 1); cursor = cursor + count; return result
    end
    while #output < size do
        local ctrl = take(24)
        local a, b, seek = offtin(ctrl, 1), offtin(ctrl, 9), offtin(ctrl, 17)
        assert(a >= 0 and b >= 0 and a + b <= size - #output, "bsdiff 输出长度越界")
        local delta = take(a)
        for index = 1, a do
            local pos = oldpos + index
            output[#output + 1] = string.char((delta:byte(index) + ((pos > 0 and pos <= #old) and old:byte(pos) or 0)) % 256)
        end
        local extra = take(b)
        for index = 1, #extra do output[#output + 1] = extra:sub(index, index) end
        oldpos = oldpos + a + seek
        assert(math.abs(oldpos) < 9007199254740992, "bsdiff 旧固件偏移溢出")
    end
    assert(cursor == #patchdata + 1, "bsdiff 有多余数据")
    return table.concat(output)
end
