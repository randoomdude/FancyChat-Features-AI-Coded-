-- Run from the repository root with LuaJIT 2.1:
--   luajit tests/performance.lua [path/to/baseline]
-- Pure Lua checks; Ashita/GDI are mocked. Optional baseline contains the
-- original lib/buffer.lua, lib/render.lua, lib/lifecycle.lua and utils.lua.
local function read(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a'):gsub('\r\n', '\n')
    f:close()
    return s
end
local function section(s, first, last)
    local a = assert(s:find(first, 1, true))
    local z = assert(s:find(last, a + #first, true))
    return s:sub(a, z - 1)
end
local function same(a, b)
    assert(type(a) == type(b))
    if type(a) ~= 'table' then assert(a == b); return end
    for k, v in pairs(a) do same(v, b[k]) end
    for k in pairs(b) do assert(a[k] ~= nil) end
end
local columns = {'text', 'mode', 'color', 'auxText', 'auxColor', 'url'}
local function rows(n, mode)
    local t = {}
    for _, k in ipairs(columns) do
        t[k] = {}
        for i = 1, n do t[k][i] = k .. i end
    end
    if mode == 'absent' then t.mode = nil end
    if mode == 'empty' then t.mode = {} end
    return t
end
local state = {fcw = {}, fo = {Chat = {}, Aux = {}}, b = {}, allSettings = {}}
package.loaded.common = true
package.loaded.imgui = {}
package.loaded.utils = {}
package.loaded['lib.state'] = state
string.trimex = function(s) return s:match('^%s*(.-)%s*$') end
local buffer = assert(loadfile('lib/buffer.lua'))()

-- Check retained rows against their original indices, including all six
-- parallel arrays and the unused mode arrays in dedicated tabs.
for _, mode in ipairs({'full', 'absent', 'empty'}) do
    for _, n in ipairs({0, 1, 12, 100, 601}) do
        for _, count in ipairs({0, 1, 50, 100, 601, 700}) do
            local t, original = rows(n, mode), rows(n, mode)
            local refs = {}; for k, v in pairs(t) do refs[k] = v end
            buffer.BulkRemove(t, count)
            for k, v in pairs(t) do
                assert(v == refs[k], 'pruning replaced an array')
                local kept = {}; for i = count + 1, n do kept[#kept + 1] = original[k][i] end
                same(v, kept)
                assert(v[n + 1] == nil)
            end
        end
        for stride = 1, 7 do
            local t, original, remove, excluded = rows(n, mode), rows(n, mode), {}, {}
            for i = stride, n, stride do remove[#remove + 1], excluded[i] = i, true end
            buffer.BulkRemoveCombat(t, remove)
            for k, v in pairs(t) do
                local kept = {}
                for i = 1, n do if not excluded[i] then kept[#kept + 1] = original[k][i] end end
                same(v, kept)
            end
        end
    end
end
local stable = rows(600)
local references = {}; for k, v in pairs(stable) do references[k] = v end
for cycle = 1, 1000 do
    buffer.BulkRemove(stable, 100)
    for _, k in ipairs(columns) do
        for i = 501, 600 do stable[k][i] = k .. (cycle * 100 + i) end
        assert(stable[k] == references[k] and #stable[k] == 600)
    end
end
print('PASS: prefix/combat pruning, empty/absent modes, 100,000-row buffer reuse')

local function byte_counter(source)
    local env = setmetatable({utils = {}, bit = require('bit')}, {__index = _G})
    local fn = assert(loadstring(section(source, 'utils.CountExtraBytesT = ', '\nend') .. '\nend'))
    setfenv(fn, env)()
    return env.utils.CountExtraBytesT
end
local count_bytes = byte_counter(read('utils.lua'))
local codec = require('lib.textcodec')
local samples = {'', 'ASCII chat ', 'caf\195\169 ', '\230\151\165\230\156\172\232\170\158',
    '\239\189\182', '\240\159\152\128', '\226\157\174word\226\157\175',
    '\30\200colored\31\01 text', '\255\192\128broken', '\226\152\133\226\153\165'}
for _, s in ipairs(samples) do
    for repeat_count = 1, 40 do
        s = s .. samples[repeat_count % #samples + 1]
        local full = count_bytes(s)
        for _, width in ipairs({1, 2, 5, 60, 85, 99, 135}) do
            local prefix = count_bytes(s, width)
            assert(#prefix == math.min(width, #full))
            for i, value in ipairs(prefix) do assert(value == full[i]) end
        end
    end
end
assert(not codec.has_japanese(('English only '):rep(300)))
assert(codec.has_japanese(('English prefix '):rep(300) .. samples[4]))
assert(not codec.has_japanese(samples[3] .. samples[6] .. samples[9]))
print('PASS: bounded UTF-8 counts preserve prefixes, colors, symbols and malformed bytes')

local baseline = arg and arg[1]
if not baseline then
    print('Baseline comparisons skipped (supply baseline directory to enable).')
    return
end
local old_count = byte_counter(read(baseline .. '/utils.lua'))
for _, s in ipairs(samples) do same(old_count(s:rep(80)), count_bytes(s:rep(80))) end

-- Exercise the real instant-scroll blocks and real UpdateLines/ResetLines
-- using font objects that record their final visible state.
local function instant(source, id)
    local marker = 'if allSettings.InstantChatScroll[1] then'
    local a = assert(source:find(marker, 1, true)) + #marker
    if id == 2 then a = assert(source:find(marker, a, true)) + #marker end
    local last = 'fcw' .. id .. '.ChatShiftScale = fcw' .. id .. '.ChatShiftScale_Min'
    local _, z = assert(source:find(last, a, true))
    local fn = assert(loadstring(source:sub(a, z)))
    local env = setmetatable({b = state.b, fo = state.fo, allSettings = state.allSettings,
        fcw1 = {}, fcw2 = {}, _fh = 14, math_max = math.max}, {__index = _G})
    setfenv(fn, env)
    return function(history, pending, lines, head)
        state.allSettings.ChatLines = lines
        state.allSettings.fontSettings = {font_height = 14}
        state.fcw[id] = {ChatHead = head, Anchor_Y = 300, ChatShiftScale_Min = 1}
        env['fcw' .. id] = state.fcw[id]
        state.fcw[1] = state.fcw[1] or {}
        state.b.ChatBuffer = {{nil, rows(history)}}
        state.b.ChatBufferMode = {[id] = 1}
        state.b.ChatBufferIdx, state.b.ChatBufferN = {[id] = 100000 - pending}, {[id] = 100000}
        local writes = 0
        for _, kind in ipairs({'Chat', 'Aux'}) do
            state.fo[kind][id] = {}
            for i = 1, lines do
                state.fo[kind][id][i] = {
                    settings = {font_color = 'oldcolor' .. i}, text = 'old' .. i, y = 300 - 14 * i,
                    visible = false, opacity = 0.5,
                    set_text = function(self, v) self.text = v; writes = writes + 1 end,
                    set_font_color = function(self, v) self.settings.font_color = v end,
                    set_position_y = function(self, v) self.y = v end,
                    set_visible = function(self, v) self.visible = v end,
                    set_opacity = function(self, v) self.opacity = v end,
                }
            end
        end
        fn()
        assert(state.b.ChatBufferIdx[id] == state.b.ChatBufferN[id])
        local result = {}
        for _, kind in ipairs({'Chat', 'Aux'}) do
            for i = 1, lines do
                local slot = (state.fcw[id].ChatHead + i - 2) % lines + 1
                local o = state.fo[kind][id][slot]
                -- A ResetLines fallback leaves positioning to the render
                -- pass. Compare content/visibility here, not that later pass.
                result[#result + 1] = {o.text, o.settings.font_color, o.visible}
            end
        end
        return result, writes
    end
end
for id = 1, 2 do
    local old = instant(read(baseline .. '/lib/render.lua'), id)
    local new = instant(read('lib/render.lua'), id)
    for _, history in ipairs({0, 1, 12, 50, 600}) do
        for _, pending in ipairs({1, 6, 11, 12, 13, 50, 100, 600, 100000}) do
            for _, lines in ipairs({1, 8, 12, 16}) do
                for _, head in ipairs({1, lines}) do
                    local before = old(history, pending, lines, head)
                    local after, writes = new(history, pending, lines, head)
                    same(before, after)
                    assert(writes <= lines * 2)
                end
            end
        end
    end
    local _, before = old(600, 600, 12, 1)
    local _, after = new(600, 600, 12, 1)
    print(('PASS: window %d backlog equivalence; 600-row burst text writes %d -> %d'):format(id, before, after))
end

local function scan(source)
    local env = {dw = {}, uiw = {NetStatObj = {}}, ashita = {memory = {}}}
    local calls, seen, addresses = 0, {}, {}
    env.ashita.memory.find = function(dll, _, pattern, offset)
        calls = calls + 1
        local key = dll .. pattern .. offset
        if not addresses[key] then addresses[key] = #seen * 100 + 1000; seen[#seen + 1] = key end
        return addresses[key]
    end
    env.ashita.memory.read_uint32 = function(p) return p + 64 end
    local src = section(source, 'local function scan_memory_pointers()', '\n\tend')
    local fn = assert(loadstring(src .. '\nend\nscan_memory_pointers()'))
    setfenv(fn, env)()
    return {env.dw, env.uiw}, calls
end
local old, old_calls = scan(read(baseline .. '/lib/lifecycle.lua'))
local new, new_calls = scan(read('lib/lifecycle.lua'))
same(old, new)
assert(old_calls == 12 and new_calls == 9)
local lifecycle = read('lib/lifecycle.lua')
assert(not lifecycle:find("'ptr_rescan_cb'", 1, true))
local zone = section(lifecycle, 'elseif e.id == 0x000A then', 'elseif e.id == 0x00E0')
assert(zone:find('scan_memory_pointers()', 1, true))
print('PASS: identical pointer values, 12 -> 9 scans, zone-in refresh retained')
print('All performance regressions passed. Live game frame timing is not simulated.')
