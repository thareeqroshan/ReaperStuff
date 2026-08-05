--[[
 * ReaScript Name: Select Previous Track And If No Track Available Insert One And Select It
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: js_ReaScriptAPI (optional, for scroll-into-view)
 * Version: 2.2
--]]

local info = debug.getinfo(1, 'S')
local ScriptPath = info.source:match([[^@?(.*[\/])[^\/]-$]])
local Nav = dofile(ScriptPath .. 'Functions/TrackNav.lua')

Nav.selectPrevious(true)
