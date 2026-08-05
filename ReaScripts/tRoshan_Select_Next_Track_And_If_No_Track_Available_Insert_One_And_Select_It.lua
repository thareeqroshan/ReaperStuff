--[[
 * ReaScript Name: Select Next Track And If No Track Available Insert One And Select It
 * Author: tRoshan
 * Licence: GPL v3
 * REAPER: 7.0
 * Extensions: js_ReaScriptAPI (optional, for scroll-into-view)
 * Version: 2.0
--]] --[[
 * Changelog:
 * v2.0 (2026-08-05)
 	+ Moved onto Functions/TrackNav.lua: hidden tracks and tracks inside collapsed folders are skipped
 * v1.0 (2024-02-16)
 	+ Initial Release
--]]

local info = debug.getinfo(1, 'S')
local ScriptPath = info.source:match([[^@?(.*[\/])[^\/]-$]])
local Nav = dofile(ScriptPath .. 'Functions/TrackNav.lua')

Nav.selectNext(true)
