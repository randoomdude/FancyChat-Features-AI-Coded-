-- Shared, reversible filters for the All tab. Dedicated tabs and raw history
-- retain their messages; buffer 2 is the current filtered view of buffer 1.
require('common')
local state = require('lib.state')
local chat_rules = require('lib.chat_rules')
local s, b, tab = state.allSettings, state.b, state.tab
local M = {}
M.options = {
    {'Unity', 'Unity'}, {'Shout', 'Shout / Yell'}, {'Say', 'Say'},
    {'Tell', 'Tell'}, {'Party', 'Party'}, {'Linkshell1', 'Linkshell 1'},
    {'Linkshell2', 'Linkshell 2'}, {'Emote', 'Emotes'}, {'NPC', 'NPC dialogue'},
    {'System', 'System messages'},
}

function M.mode(value)
    return (tostring(value or ''):gsub('^%d+|', ''))
end

function M.enabled()
    if s.HideCombatFromAll[1] then return true end
    local filters = s.HideFromAll or {}
    for _, option in ipairs(M.options) do
        if filters[option[1]] == true then return true end
    end
    return false
end

function M.hidden(value)
    local mode = M.mode(value)
    local custom = mode:find('@$') ~= nil
    mode = mode:gsub('@+$', '')
    if s.HideCombatFromAll[1] and (custom or mode:find('^combat')) then return true end
    local f = s.HideFromAll or {}
    return (f.Unity == true and mode:find('^unity') ~= nil)
        or (f.Shout == true and mode:find('^shout') ~= nil)
        or (f.Say == true and mode == 'local')
        or (f.Tell == true and mode:find('^tell') ~= nil)
        or (f.Party == true and mode:find('^party') ~= nil)
        or (f.Linkshell1 == true and mode:find('^linkshell1') ~= nil)
        or (f.Linkshell2 == true and mode:find('^linkshell2') ~= nil)
        or (f.Emote == true and mode:find('^emote') ~= nil)
        or (f.NPC == true and mode:find('NPC$') ~= nil)
        or (f.System == true and chat_rules.is_system(mode))
end

function M.rebuild()
    local raw, view = b.ChatBuffer[1][2], b.ChatBuffer[2][2]
    local columns = {'text', 'mode', 'color', 'auxText', 'auxColor', 'url'}
    for _, key in ipairs(columns) do view[key] = {} end
    for i = 1, #raw.text do
        if not M.hidden(raw.mode[i]) then
            for _, key in ipairs(columns) do
                local value = raw[key][i]
                if key == 'mode' then value = value or '0|system' end
                view[key][#view[key] + 1] = value
            end
        end
    end
    b.ChatBufferN_AllAlt = #view.text
end

function M.refresh()
    M.rebuild()
    local target = M.enabled() and 'AllAlt' or 'All'
    tab.Tabs[1] = target
    for i = 1, (s.SecondChat[1] and 2 or 1) do
        local key = i == 1 and 'SelectedTab' or 'SelectedTab2'
        if s[key] == 'All' or s[key] == 'AllAlt' then
            if i == 1 then tab.NextTab = target else tab.NextTab2 = target end
            b.ChatBufferN[i] = target == 'AllAlt' and b.ChatBufferN_AllAlt or b.ChatBufferN_All
            ChangeTab(i, target)
            ResetScrolling(i)
            state.fcw[i].RequestAuxFix = true
        end
    end
    if state.fcw[3].BigMode then
        b.ChatBufferIdx[3] = b.ChatBufferIdx[1]
        ResetScrolling(3, state.fcw[3].ChatLines)
    end
end

-- Mirror combat-cap pruning into the filtered view. Count the exact accepted
-- rows from the raw removal list, then remove that many oldest combat rows.
function M.trim_combat(raw_indices)
    local raw, view = b.ChatBuffer[1][2], b.ChatBuffer[2][2]
    local count = 0
    for _, index in ipairs(raw_indices) do
        if not M.hidden(raw.mode[index]) then count = count + 1 end
    end
    if count == 0 then return end
    local indices = {}
    for i, mode in ipairs(view.mode) do
        if M.mode(mode):find('^combat') then indices[#indices + 1] = i end
        if #indices == count then break end
    end
    BulkRemoveCombat(view, indices)
end

function M.draw_options()
    local imgui = require('imgui')
    s.HideFromAll = s.HideFromAll or T{}
    imgui.Text('Hide these chat types from All:')
    for _, option in ipairs(M.options) do
        local key, label = option[1], option[2]
        local value = {s.HideFromAll[key] == true}
        if imgui.Checkbox(label .. '##HideFromAll', value) then
            s.HideFromAll[key] = value[1]
            M.refresh()
            SaveSettings()
        end
    end
    imgui.TextWrapped('Applies immediately to All in both windows. Dedicated tabs and saved raw history keep these messages. Turn a toggle off to show retained history again.')
end

return M
