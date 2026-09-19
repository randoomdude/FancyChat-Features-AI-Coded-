-- Resolution layouts for the user's modular FancyChat 1.0.260721R.
-- Only geometry is copied. Filters, colors, bindings, tabs and other behavior
-- remain in the original flat allSettings table. No global settings hooks.
require('common')
local imgui = require('imgui')
local settings = require('settings')
local state = require('lib.state')
local s = state.allSettings
local M = {}
local active, owner, suspended, queued
local pending_pos = {}
local candidate, candidate_since
local edit_name, draft

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = T{}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

local function number(value, fallback, low, high)
    if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then
        return fallback
    end
    return math.max(low, math.min(high, math.floor(value + 0.5)))
end

local function identity()
    return tostring(settings.name) .. ':' .. tostring(settings.server_id)
end

function M.classify(width, height)
    if type(width) ~= 'number' or type(height) ~= 'number'
        or width ~= width or height ~= height
        or width < 640 or height < 480
        or width == math.huge or height == math.huge then return nil end
    return width >= 2400 and 'Desktop' or 'Laptop'
end

local function display()
    local d = imgui.GetIO().DisplaySize
    return tonumber(d.x), tonumber(d.y)
end

local function size(p)
    return p.FontSize * p.ChatWidth * 0.59,
        p.FontSize * (p.ChatLines + 1) + p.FontSize / 5 + 16
end

local function snapshot()
    return T{
        FontSize = s.fontSettings.font_height,
        ChatWidth = s.chatLineMaxL,
        ChatLines = s.ChatLines,
        Offsets = copy(s.WindowPosOffset),
        Windows = T{},
    }
end

local function clean(p, fallback)
    p = type(p) == 'table' and p or T{}
    p.FontSize = number(p.FontSize, fallback.FontSize, 14, 50)
    p.ChatWidth = number(p.ChatWidth, fallback.ChatWidth, 60, 135)
    p.ChatLines = number(p.ChatLines, fallback.ChatLines, 8, 16)
    p.Offsets = type(p.Offsets) == 'table' and p.Offsets or T{}
    p.Windows = type(p.Windows) == 'table' and p.Windows or T{}
    for i = 1, 4 do p.Offsets[i] = number(p.Offsets[i], fallback.Offsets[i], -4096, 4096) end
    for i = 1, 2 do
        local w = type(p.Windows[i]) == 'table' and p.Windows[i] or T{}
        local f = fallback.Windows[i] or {X = 60, Y = 60}
        w.X = number(w.X, f.X, -16384, 16384)
        w.Y = number(w.Y, f.Y, -16384, 16384)
        p.Windows[i] = w
    end
    return p
end

-- Read only the two existing ImGui position entries, without executing config.
-- This imports the user's Laptop placement even on a first Desktop launch.
local function legacy_positions(name)
    local positions = T{}
    local path = AshitaCore:GetInstallPath() .. '/config/imgui.ini'
    local file = io.open(path, 'r')
    if not file then return positions end
    local wanted = {
        ['[Window][FancyChat_ChatBG_' .. name .. ']'] = 1,
        ['[Window][FancyChat_ChatBG2_' .. name .. ']'] = 2,
    }
    local index
    for line in file:lines() do
        line = line:gsub('\r$', '')
        if line:sub(1, 1) == '[' then index = wanted[line] end
        if index then
            local x, y = line:match('^Pos=([%-%.%d]+),([%-%.%d]+)')
            if x and y then positions[index] = T{X = tonumber(x), Y = tonumber(y)} end
        end
    end
    file:close()
    return positions
end

local function desktop_from(laptop)
    local p = copy(laptop)
    p.FontSize = number(laptop.FontSize * 4 / 3, 19, 14, 50)
    p.ChatLines = math.min(16, laptop.ChatLines + 1)
    local _, old_h = size(laptop)
    local _, new_h = size(p)
    for i = 1, 4 do p.Offsets[i] = math.floor(p.Offsets[i] * 4 / 3 + 0.5) end
    for i = 1, 2 do
        p.Windows[i].X = math.floor(laptop.Windows[i].X * 4 / 3 + 0.5)
        -- Keep the bottom margin proportional while adding a line of text.
        p.Windows[i].Y = math.floor(1440 - (1080 - laptop.Windows[i].Y - old_h) * 4 / 3 - new_h + 0.5)
    end
    return p
end

local function apply(p)
    s.fontSettings.font_height = p.FontSize
    s.chatLineMaxL = p.ChatWidth
    s.ChatLines = p.ChatLines
    for i = 1, 4 do s.WindowPosOffset[i] = p.Offsets[i] end
end

function M.capture()
    if suspended or not active or owner ~= identity() then return end
    local p = s.LayoutProfiles[active]
    if not p then return end
    p.FontSize, p.ChatWidth, p.ChatLines = s.fontSettings.font_height, s.chatLineMaxL, s.ChatLines
    for i = 1, 4 do p.Offsets[i] = s.WindowPosOffset[i] end
end

function M.load()
    active, suspended, queued = nil, false, false
    owner = identity()
    pending_pos, candidate, draft, edit_name = {}, nil, nil, nil
    local bank = type(s.LayoutProfiles) == 'table' and s.LayoutProfiles or T{}
    local baseline = snapshot()
    local name = settings.name ~= '' and settings.name or s.PlayerName
    baseline.Windows = legacy_positions(name or '')
    baseline = clean(baseline, {
        FontSize = 14, ChatWidth = 99, ChatLines = 11, Offsets = {0, 0, 0, 0},
        Windows = {{X = 132, Y = 866}, {X = 952, Y = 863}},
    })
    bank.Laptop = clean(bank.Laptop, baseline)
    bank.Desktop = clean(bank.Desktop, desktop_from(bank.Laptop))
    bank.Version = 1
    s.LayoutProfiles = bank
    local width, height = display()
    active = M.classify(width, height)
    if active then
        apply(bank[active])
        pending_pos = {true, true}
    end
    -- Character changes replace the settings cache. Stop the old renderer and
    -- reload once login completes, without copying outgoing geometry into it.
    -- Ashita's register() lowercases aliases, but load()/save() do not.
    -- Register on the existing mixed-case entry so no empty 'allsettings'
    -- cache entry is created and serialized during login/logout. Preserve the
    -- established allSettings.lua filename and any other event callbacks.
    local cached = settings.cache['allSettings']
    cached.events = cached.events or T{}
    cached.events['fc_resolution_layouts'] = function(loaded)
        suspended = true
        state.replace_allSettings(loaded)
        state.fcw[1].Closing = true
    end
end

local function reload()
    if queued then return end
    queued = true
    state.fcw[1].Closing = true
    AshitaCore:GetChatManager():QueueCommand(1, '/addon reload fancychat')
end

function M.tick()
    if queued then return true end
    if suspended then
        local player = GetPlayerEntity()
        if settings.logged_in and player and player.ServerId and player.ServerId ~= 0 then reload() end
        return true
    end
    local width, height = display()
    local selected = M.classify(width, height)
    if not selected or selected == active then candidate = nil; return false end
    if candidate ~= selected then candidate, candidate_since = selected, os.clock(); return false end
    -- Ignore transient sizes during minimize/device reset. The old geometry is
    -- saved before a normal addon reload rebuilds the GDI objects and buffers.
    if os.clock() - candidate_since >= 1 and settings.logged_in then
        M.capture()
        settings.save('allSettings')
        reload()
        return true
    end
    return false
end

function M.before_window(index)
    if not active or not pending_pos[index] or suspended then return end
    local p = s.LayoutProfiles[active]
    local width, height = display()
    if not M.classify(width, height) then return end
    local w, h = size(p)
    local ox, oy = p.Offsets[index * 2 - 1], p.Offsets[index * 2]
    local pos = p.Windows[index]
    -- Limit initial placement to the visible game area, including fine offsets.
    local x = math.max(0, math.min(pos.X, math.max(0, width - w - math.max(ox, 0) - 8)))
    local y = math.max(0, math.min(pos.Y, math.max(0, height - h - math.max(oy, 0) - 8)))
    imgui.SetNextWindowPos({x, y}, ImGuiCond_Always)
    pending_pos[index] = nil
end

function M.record_window(index)
    if not active or suspended or owner ~= identity() then return end
    local x, y = imgui.GetWindowPos()
    local p = s.LayoutProfiles[active].Windows[index]
    -- Read the real window position before menu/cutscene shifts alter only the
    -- drawn text. In-memory updates are persisted by normal saves and unload.
    p.X, p.Y = x, y
end

local function input(label, values, key, low, high)
    local v = {values[key]}
    if imgui.InputInt(label, v) then values[key] = number(v[1], values[key], low, high) end
end

function M.draw_editor()
    local width, height = display()
    imgui.Text(('Automatic: %s (%dx%d)'):format(active or 'Waiting for game', width or 0, height or 0))
    imgui.Text('1920x1080: Laptop    2560x1440: Desktop')
    imgui.Text('Game widths of 2400 or more use Desktop.')
    imgui.Text('Select a layout to edit; automatic switching stays on.')
    if not active then return end
    if not draft then
        M.capture()
        edit_name, draft = active, copy(s.LayoutProfiles[active])
    end
    if imgui.Button('Edit Laptop') then
        M.capture(); edit_name, draft = 'Laptop', copy(s.LayoutProfiles.Laptop)
    end
    imgui.SameLine()
    if imgui.Button('Edit Desktop') then
        M.capture(); edit_name, draft = 'Desktop', copy(s.LayoutProfiles.Desktop)
    end
    imgui.Separator()
    imgui.Text('Editing: ' .. edit_name)
    imgui.PushItemWidth(150)
    input('Font size', draft, 'FontSize', 14, 50)
    input('Chat width (characters)', draft, 'ChatWidth', 60, 135)
    input('Chat lines', draft, 'ChatLines', 8, 16)
    local w, h = size(draft)
    imgui.Text(('Both windows: approximately %dx%d pixels'):format(w, h))
    imgui.Text('Both chat windows share font, width and line count.')
    for i = 1, 2 do
        imgui.Separator()
        imgui.Text('Window ' .. i .. (i == 2 and ' (second chat)' or ''))
        input('X##layout' .. i, draft.Windows[i], 'X', 0, 16384)
        input('Y##layout' .. i, draft.Windows[i], 'Y', 0, 16384)
        input('Fine X offset##layout' .. i, draft.Offsets, i * 2 - 1, -4096, 4096)
        input('Fine Y offset##layout' .. i, draft.Offsets, i * 2, -4096, 4096)
    end
    imgui.PopItemWidth()
    imgui.Separator()
    imgui.Text('Filters, colors, shortcuts and second-chat enable stay shared.')
    local current = edit_name == active
    if imgui.Button(current and 'Save layout & restart FancyChat' or 'Save layout') then
        M.capture()
        s.LayoutProfiles[edit_name] = clean(copy(draft), s.LayoutProfiles[edit_name])
        if current then
            -- Keep live flat geometry untouched until the GDI renderer reloads.
            -- Suppress unload capture so it cannot overwrite the edited bank.
            suspended = true
        end
        settings.save('allSettings')
        if current then reload() end
    end
    imgui.SameLine()
    if imgui.Button('Discard edits') then draft = nil end
    imgui.Text('Saving the active layout restarts FancyChat, clearing its backlog.')
    imgui.Text('Chat Window settings and dragging update only the active layout.')
end

return M
