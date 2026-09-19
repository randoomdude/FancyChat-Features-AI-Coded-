-- Shared message classification and native NPC-window preservation.
-- No native memory calls: the existing render loop owns window access.
local M = {}
local npc_until = 0

local function mode_name(value)
    return (tostring(value or ''):gsub('^%d+|', ''):gsub('@+$', ''))
end

function M.is_npc(value)
    return mode_name(value):find('NPC$') ~= nil
end

function M.is_system(value)
    local name = mode_name(value)
    -- NPC system lines belong to NPC, even though their name starts 'system'.
    return not M.is_npc(name) and (name:find('^system') ~= nil
        or name == 'servermsg' or name == 'echo')
end

function M.preserve_npc(settings)
    return not settings.ShowNPCInLegacy or settings.ShowNPCInLegacy[1] ~= false
end

function M.note_message(mode)
    -- Ambient NPC speech can arrive outside an event. Give the native window
    -- time to display it normally; active events are protected for their full
    -- duration by should_pin_legacy(), including pauses between dialog pages.
    if M.is_npc(mode) then npc_until = os.clock() + 15 end
end

function M.reset_npc()
    npc_until = 0
end

function M.should_pin_legacy(settings, hidden, in_event)
    if hidden or settings.ShowWithLegacy[1] then return false end
    if M.preserve_npc(settings) and (in_event or os.clock() < npc_until) then return false end
    return true
end

return M
