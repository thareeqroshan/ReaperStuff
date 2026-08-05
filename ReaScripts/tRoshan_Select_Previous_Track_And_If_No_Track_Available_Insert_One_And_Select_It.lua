--[[
 * ReaScript Name: Select Previous Track And If No Track Available Insert One And Select It
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: None
 * Version: 1.0
--]] --[[
 * Changelog:
 * v1.0 (2024-02-16)
 	+ Initial Release
--]]

local info = debug.getinfo(1, 'S')
local ScriptPath = info.source:match([[^@?(.*[\/])[^\/]-$]])
local Nav = dofile(ScriptPath .. 'Functions/TrackNav.lua')

Nav.selectPrevious(true)
