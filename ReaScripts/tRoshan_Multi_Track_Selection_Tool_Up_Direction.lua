--[[
 * ReaScript Name: Multi Track Selection Tool (Up Direction)
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: js_ReaScriptAPI (optional, for scroll-into-view)
 * Version: 2.0
--]]

local info = debug.getinfo(1, 'S')
local ScriptPath = info.source:match([[^@?(.*[\/])[^\/]-$]])
local Nav = dofile(ScriptPath .. 'Functions/TrackNav.lua')

-- Extend the track selection upward by one visible track.
Nav.extendUp()