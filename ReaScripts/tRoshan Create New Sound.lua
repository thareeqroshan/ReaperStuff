--[[
* ReaScript Name: tRoshan Create New Sound
* Description: Setup sfx for Game Audio
* Author: tRoshan
* File URI:
* License: MIT
* Forum Thread:
* Forum Thread URI:
* REAPER: 7.x
* Extensions: None
* Version: 1.0
--]] function Msg(str)
    reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

function printTable(t)
    for k, v in pairs(t) do
        Msg(k .. " : " .. v)
    end
end

function ListTrackTemplates(path, templates)
    files = reaper.EnumerateFiles(path, 0)
    local i = 0
    repeat
        local file = reaper.EnumerateFiles(path, i)
        if file then
            -- Assuming track templates end with ".RTrackTemplate"
            if file:match("%.RTrackTemplate$") then
                table.insert(templates, file)
            end
            i = i + 1
        end
    until not file

    local i = 0
    repeat
        local directory = reaper.EnumerateSubdirectories(path, i)
        if directory then
            -- Assuming track templates end with ".RTrackTemplate"
            ListTrackTemplates(path .. "/" .. directory, templates)
            i = i + 1
        end
    until not directory
end

function GetTrackTemplates()
    local resourcePath = reaper.GetResourcePath()
    local trackTemplatesPath = resourcePath .. "/TrackTemplates"
    local templates = {}
    ListTrackTemplates(trackTemplatesPath, templates)
    local i = 0
    local directory = reaper.EnumerateSubdirectories(trackTemplatesPath, i)

    return templates
end

-- Helper function to convert RGB to Reaper's native color format
function RGBToNative(r, g, b)
    return (r << 16) + (g << 8) + b | 0x1000000
end

local folder_idx

-- Define a table of aesthetically pleasing colors in RGB
local colors = {RGBToNative(255, 99, 71), -- Tomato
RGBToNative(135, 206, 250), -- Light Sky Blue
RGBToNative(60, 179, 113), -- Medium Sea Green
RGBToNative(255, 165, 0), -- Orange
RGBToNative(238, 130, 238), -- Violet
RGBToNative(70, 130, 180) -- Steel Blue
}

-- GUI
package.path = reaper.GetResourcePath() .. '/Scripts/rtk/1/?.lua'
-- Now we can load the rtk library.
local rtk = require('rtk')
local color = colors[math.random(#colors)]

function refreshColor()
    color = colors[math.random(#colors)]
end

-- Create an rtk.Window object that is to be the main application window
local window = rtk.Window({
    w = 600,
    h = 250,
    title = "Create New Sound",
    padding = 0,
    borderless = true,
    color = 'black'
})
local label_width = 100
function getRandomSoundEffectName()
    local names = {"Boing", "Whizz", "Splat", "Zap", "Ping", "Plop", "Kaboom", "Meow"}
    return names[math.random(#names)]
end
-- Create a new button initialized with this label.  Note the curly braces,
-- because all rtk.Widget classes actually receive a table of attributes
-- upon initialization.  This one is a special "positional" value that
-- corresponds to the 'label' attribute.  We also add a 20px margin around
-- the button to add some spacing between it and the window border.
local window_name_text = rtk.Text {
    text = "Create New Sound",
    fontflags = rtk.font.BOLD,
    halign = 'center',
    valign = 'center',
    minh = 20,
    maxh = 20,
    fillw = true
}

local sound_name_label = rtk.Text {
    text = "Sound Name",
    fontflags = rtk.font.BOLD,
    w = label_width
}
local generatedName = getRandomSoundEffectName()
local sound_name_entry = rtk.Entry {
    value = generatedName,
    placeholder = generatedName,
    textwidth = 10
}
num_variations_text = rtk.Text {
    text = "Variations",
    fontflags = rtk.font.BOLD,
    w = label_width
}
-- convert table of numbers to table of strings
items = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
for i, v in ipairs(items) do
    items[i] = tostring(v)
end
num_variations = rtk.OptionMenu {
    menu = items,
    selected = 5
}

duration_text = rtk.Text {
    text = "Length",
    fontflags = rtk.font.BOLD,
    w = label_width
}

duration_slider = rtk.Slider {
    min = 0.1,
    max = 30,
    value = 5,
    step = 0.1,
    color = 'crimson'
}
duration_value = rtk.Text {
    text = "5.0"
}
duration_slider.onchange = function(self)
    duration_value:attr('text', tostring(self.value))
end

duration_box = rtk.HBox {
    spacing = 10
}
duration_box:add(duration_text)
duration_box:add(duration_slider)
duration_box:add(duration_value)

track_templates_list = GetTrackTemplates()
-- create a new option menu with the list of track templates
track_templates_menu = rtk.OptionMenu {
    menu = track_templates_list,
    selected = 1
}

track_templates_text = rtk.Text {
    text = "Track Template",
    fontflags = rtk.font.BOLD,
    w = label_width
}
track_template_box = rtk.HBox {
    spacing = 10
}
track_template_box:add(track_templates_text)
track_template_box:add(track_templates_menu)

title_box = rtk.HBox {
    spacing = 10,
    bg = color
}

local button = rtk.Button {'Create Sound'}
-- Add an onclick handler to respond to mouse clicks of the button
button.onclick = function(self, event)
    -- Animate the button color to red and change the label.
    -- button:animate{
    --     'color',
    --     dst = 'green'
    -- }
    local sound_name = sound_name_entry.value
    local num_variations = tonumber(num_variations.selected)
    local variation_length = tonumber(duration_slider.value)
    if sound_name and num_variations and variation_length then
        reaper.Undo_BeginBlock()
        CreateTracksAndFolder(sound_name, num_variations, color)
        CreateRegionsWithPadding(sound_name, num_variations, variation_length, color)
        reaper.Undo_EndBlock("Create New Sound : " .. sound_name, 0)
        refreshColor()
        title_box:attr('bg', color)
        sound_name_entry:attr('value', getRandomSoundEffectName())
    end
end

-- add close button
local close_button = rtk.Button {'Close'}
close_button.onclick = function(self, event)
    window:close()
end
-- Add the button widget to window, centered within it.  In practice you
-- would probably use a series of box container widgets to craft a layout.

vBox = rtk.VBox {
    spacing = 10
}
number_of_variations_box = rtk.HBox {
    spacing = 10
}

number_of_variations_box:add(num_variations_text)
number_of_variations_box:add(num_variations)
sound_name_entry:select_all()
sound_name_entry:focus()
sound_name_box = rtk.HBox {
    spacing = 10
}
sound_name_box:add(sound_name_label)
sound_name_box:add(sound_name_entry)
-- local title_color = colors[math.random(#colors)]

-- title_box:stretch()
title_box:add(window_name_text, {
    halign = 'center',
    valign = 'center',
    fillw = true
})

action_bar_box = rtk.HBox {
    spacing = 10,
    padding = 10
}
action_bar_box:add(button)
action_bar_box:add(close_button)

vBox:add(title_box, {
    halign = 'center'
})
vBox:add(sound_name_box, {
    -- halign = 'center'
    tpadding = 10
})
vBox:add(number_of_variations_box)
vBox:add(track_template_box)
vBox:add(duration_box)
window:add(vBox, {
    halign = 'center',
    padding = 20
})

window:add(action_bar_box, {
    halign = 'center',
    valign = 'bottom'
})

-- Finally open the window, which we place in the center of the screen.
window:open{
    align = 'center',
    borderless = true
}

-- Function to set a random color from the preset to a track
function setTrackColor(track, color)
    reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", color)
    return color
end

-- Function to gather user inputs
function GetUserInputs()
    local ret, inputs = reaper.GetUserInputs("Sound Design Setup", 3,
        "Sound Name,Number of Variations,Length of Each Variation", "")
    if not ret then
        return
    end

    local sound_name, num_variations, variation_length = inputs:match("([^,]+),([^,]+),([^,]+)")
    num_variations = tonumber(num_variations)
    variation_length = tonumber(variation_length)

    return sound_name, num_variations, variation_length
end

-- Function to create folder and tracks
function CreateTracksAndFolder(sound_name, num_variations, color)
    -- Insert the folder track at the correct index
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    folder_idx = reaper.CountTracks(0) - 1 -- Adjusting for 0-based indexing
    local folder_track = reaper.GetTrack(0, folder_idx)
    reaper.GetSetMediaTrackInfo_String(folder_track, "P_NAME", sound_name, true)
    reaper.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
    setTrackColor(folder_track, color)

    local track_number = 8
    for i = 1, track_number do
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local track_idx = reaper.CountTracks(0) - 1 -- Adjusting for 0-based indexing after each insertion
        local track = reaper.GetTrack(0, track_idx)
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", sound_name .. " " .. i, true)
        -- Make the track a child of the folder track by adjusting folder depth
        -- if i == 1 then
        -- reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 1)
        -- else
        reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
        setTrackColor(track, color)
        -- end
    end
    -- Finalizing the folder structure
    reaper.SetMediaTrackInfo_Value(reaper.GetTrack(0, reaper.CountTracks(0) - 1), "I_FOLDERDEPTH", -1)
end

-- Adjusting region creation to include padding
-- Assuming RGBToNative and colors table are defined as in the previous example

-- Function to create regions with padding and color them
function CreateRegionsWithPadding(sound_name, num_variations, variation_length, color)
    local start_pos = reaper.GetCursorPosition()
    local padding = variation_length / 2 -- Calculate padding
    local track = reaper.GetTrack(0, folder_idx)
    for i = 1, num_variations do
        local region_name = sound_name .. " " .. i .. "_Play"
        regionindex = reaper.AddProjectMarker2(0, true, start_pos, start_pos + variation_length, region_name, -1, color)
        start_pos = start_pos + variation_length + padding -- Include padding for the next start position
        reaper.SetRegionRenderMatrix(0, regionindex, track, 1)
    end
end

-- Main script
-- local sound_name, num_variations, variation_length = GetUserInputs()
-- local color = colors[math.random(#colors)]
-- if sound_name and num_variations and variation_length then
--     CreateTracksAndFolder(sound_name, num_variations, color)
--     CreateRegionsWithPadding(sound_name, num_variations, variation_length)
-- end
