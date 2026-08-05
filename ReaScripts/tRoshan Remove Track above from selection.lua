--[[
 * ReaScript Name: Remove Track above from selection
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: None
 * Version: 2.0
--]]

local info = debug.getinfo(1, 'S')
local ScriptPath = info.source:match([[^@?(.*[\/])[^\/]-$]])
local Nav = dofile(ScriptPath .. 'Functions/TrackNav.lua')

Nav.shrinkTop()
