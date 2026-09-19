-- FFXI Shift-JIS decoding and Japanese display helpers.
-- The generated CP932 map is local data; no locale-dependent native calls.
local cp932 = require('lib.cp932')
local M = {}
local replacement = '\239\191\189'
local byte, sub = string.byte, string.sub

local function continuation(b) return b and b >= 0x80 and b <= 0xBF end

function M.next_utf8(text, i)
    local a, b, c, d = byte(text, i, i + 3)
    if not a then return nil, i end
    if a < 0x80 then return a, i + 1 end
    if a >= 0xC2 and a <= 0xDF and continuation(b) then
        return (a - 0xC0) * 64 + b - 0x80, i + 2
    end
    if a >= 0xE0 and a <= 0xEF and continuation(b) and continuation(c)
        and (a ~= 0xE0 or b >= 0xA0) and (a ~= 0xED or b < 0xA0) then
        return (a - 0xE0) * 4096 + (b - 0x80) * 64 + c - 0x80, i + 3
    end
    if a >= 0xF0 and a <= 0xF4 and continuation(b) and continuation(c) and continuation(d)
        and (a ~= 0xF0 or b >= 0x90) and (a ~= 0xF4 or b < 0x90) then
        return (a - 0xF0) * 262144 + (b - 0x80) * 4096 + (c - 0x80) * 64 + d - 0x80, i + 4
    end
    return 0xFFFD, i + 1
end

local function japanese(cp)
    return (cp >= 0x2E80 and cp <= 0xA4CF)
        or (cp >= 0xF900 and cp <= 0xFAFF)
        or (cp >= 0xFF01 and cp <= 0xFFEF)
        or (cp >= 0x20000 and cp <= 0x2FA1F)
end

function M.has_japanese(text)
    local i = 1
    while i <= #text do
        local cp, next_i = M.next_utf8(text, i)
        if japanese(cp) then return true end
        i = next_i
    end
    return false
end

function M.columns(cp)
    if cp >= 0xFF61 and cp <= 0xFF9F then return 1 end -- half-width kana
    if cp == 0x3099 or cp == 0x309A then return 0 end
    if japanese(cp) or (cp >= 0x1F300 and cp <= 0x1FAFF) then return 2 end
    return 1
end

-- A byte index ending at a complete UTF-8 character and within the column
-- budget. Legacy palette escapes occupy zero columns and stay in one piece.
function M.wrap_index(text, limit)
    local i, last, used = 1, 0, 0
    while i <= #text do
        local b = byte(text, i)
        if (b == 0x1E or b == 0x1F) and i < #text then
            last, i = i + 1, i + 2
        else
            local cp, next_i = M.next_utf8(text, i)
            local width = M.columns(cp)
            if used + width > limit then break end
            used, last, i = used + width, next_i - 1, next_i
        end
    end
    return last
end

function M.safe_end(text, limit)
    local i, last = 1, 0
    while i <= #text do
        local _, next_i = M.next_utf8(text, i)
        if next_i - 1 > limit then break end
        last, i = next_i - 1, next_i
    end
    return last
end

function M.decode(text, overrides, drops, preserve_colors)
    local out, i = {}, 1
    while i <= #text do
        local b, tail = byte(text, i, i + 1)
        if b == 0x1E or b == 0x1F then
            if tail and preserve_colors then out[#out + 1] = sub(text, i, i + 1) end
            i = i + (tail and 2 or 1)
        elseif b == 0x7F then
            local third = byte(text, i + 2)
            i = i + ((tail and tail >= 0x31 and tail <= 0x37 and third and third >= 1 and third <= 6) and 3 or 2)
        elseif b >= 0x20 and b <= 0x7E then
            out[#out + 1], i = string.char(b), i + 1
        elseif b >= 0xA1 and b <= 0xDF then
            out[#out + 1], i = cp932[b], i + 1
        else
            -- Preserve the existing addon's supported UTF-8 supplementary
            -- icons, but require a complete valid sequence before doing so.
            local cp, next_i = M.next_utf8(text, i)
            if b >= 0xF0 and b <= 0xF4 and next_i == i + 4 then
                out[#out + 1], i = sub(text, i, next_i - 1), next_i
            elseif (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC) then
                local pair = sub(text, i, i + 1)
                if drops and drops[pair] then
                    i = i + 2
                elseif overrides[pair] then
                    out[#out + 1], i = overrides[pair], i + 2
                elseif tail and ((tail >= 0x40 and tail <= 0x7E) or (tail >= 0x80 and tail <= 0xFC)) then
                    out[#out + 1], i = cp932[b * 256 + tail] or replacement, i + 2
                else
                    out[#out + 1], i = replacement, i + 1
                end
            else
                i = i + 1
            end
        end
    end
    return table.concat(out)
end

return M
