-- @noindex
--[[
 * ReaScript Name: Select previous track or insert one
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: js_ReaScriptAPI (optional, for scroll-into-view)
--]]

local info = debug.getinfo(1, 'S')
local ScriptPath = info.source:match([[^@?(.*[\/])[^\/]-$]])
local Nav = dofile(ScriptPath .. 'Functions/TrackNav.lua')

Nav.selectPrevious(true)
