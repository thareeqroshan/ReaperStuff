import dearpygui.dearpygui as dpg
import model
import os, os.path
from reathon.nodes import *
import tkinter as tk
from tkinter import filedialog

def create_project(sender, app_data):

    if os.path.isdir(dpg.get_value(root_folder_path_id)):
        asset_name = dpg.get_value(type_of_sound_id) + "_" + dpg.get_value(asset_name_id)
        num_variations = dpg.get_value(num_variations_id)

        data = []
        region_seperation = 5
        time = 10
        region_count = 1

        for i in range(0,len(list_of_sounds)):
            list_of_sounds[i] = dpg.get_value("sound"+str(i+1))
            variation = dpg.get_value("variation"+str(i+1))
            duration = dpg.get_value("duration"+str(i+1))
            tracks_num = dpg.get_value("tracksnum" + str(i+1))
            data.append([list_of_sounds[i], variation, duration,tracks_num])
        print(data)

        print(f'Creating {asset_name} project with {num_variations} variations')
        # projectFolder = os.path.join(os.path.dirname(os.path.realpath(__file__)), "projects")
        folderPath = os.path.join(dpg.get_value(root_folder_path_id),asset_name)
        if not os.path.isdir(folderPath):
            os.mkdir(folderPath)
        project = Project()
        for sound in data:
            sound[3] +=1
            for num in range(1,sound[3] + 1):
                track_name =  sound[0] if num ==1 else sound[0] + str(num - 1)
                track = Track()
                
                if sound[3] ==1:
                    props = [
                        ["NAME", sound[0]]
                    ]
                elif num == 1 :
                    props = [
                        ["NAME", sound[0]],
                        ["ISBUS", [1, 1]]
                    ]
                elif num ==sound[3]:
                    props = [
                        ["NAME", track_name],
                        ["ISBUS", [2, -1]]
                    ]
                else:
                    props = [
                        ["NAME", track_name]
                    ]
                track.props = props
                project.add(track)
                
            for i in range(1,sound[1]+1):
                project.add_region(region_count, time, time + sound[2], sound[0] + str(i))
                time = time + sound[2] + region_seperation
                region_count +=1
        projectPath = os.path.join(folderPath,(asset_name + ".rpp"))
        project.write(projectPath)

def root_folder_picker(sender, data):
    root = tk.Tk()
    root.withdraw()

    root_folder_path = filedialog.askdirectory()
    dpg.set_value(root_folder_path_id,root_folder_path)

def change_type_sound():
    dpg.set_item_label(asset_name_id, "Name of the "+ dpg.get_value(type_of_sound_id))

def rgb_to_long_int(r, g, b):
    return (r + g * 256 + b * 256 * 256)

list_of_sounds = ["sound1"]


def add_sound():
    name = "sound" +str(len(list_of_sounds) + 1)
    variations_name = "variation" +str(len(list_of_sounds) + 1)
    durations_name = "duration" +str(len(list_of_sounds) + 1)
    tracks_num_name = "tracksnum" +str(len(list_of_sounds) + 1)
    list_of_sounds.append(name)
    with dpg.group(horizontal=True, before=add_sounds_button_id):
        dpg.add_input_text(default_value= list_of_sounds[-1], tag=list_of_sounds[-1],width=100)
        dpg.add_input_int(label="variations", width=60, default_value=4, min_value=1, min_clamped=True, tag= variations_name, indent=0)
        dpg.add_input_int(label="Tracks:", width=60, default_value=4, min_value=1, min_clamped=True, tag= tracks_num_name)
        dpg.add_slider_float(label="Duration", width=100, tag= durations_name, max_value=20.0)


WIDTH  = 600
HEIGHT = 600

dpg.create_context()

#Create some tags
asset_name_id = dpg.generate_uuid()
num_variations_id = dpg.generate_uuid()
type_of_sound_id = dpg.generate_uuid()
root_folder_path_id = dpg.generate_uuid()
track_num_id = dpg.generate_uuid()
type_of_sounds = ["sfx","music"]
sounds_group_id = dpg.generate_uuid()
add_sounds_button_id = dpg.generate_uuid()
variations_id = dpg.generate_uuid()
sound_id = dpg.generate_uuid()


dpg.create_viewport(title='ReaProject', width=WIDTH, height=HEIGHT)

with dpg.window(label='ReaProject', width=WIDTH, height=HEIGHT,horizontal_scrollbar=True):
    dpg.add_text("Welcome to the ReaProject terminal")
    with dpg.group(horizontal=True):
        dpg.add_button(label="Directory Selector", callback=root_folder_picker)
        dpg.add_text(tag=root_folder_path_id)
    dpg.add_combo(label="Type of sound",items=type_of_sounds,default_value=type_of_sounds[0], tag=type_of_sound_id, callback=change_type_sound)
    type_of_sound = dpg.get_value(type_of_sound_id)
    dpg.add_input_text(label="Name of the "+ type_of_sound , tag=asset_name_id)
    with dpg.group(horizontal=True, tag=sounds_group_id):
        dpg.add_input_text(default_value= list_of_sounds[0], tag="sound1",width=100, indent=0)
        dpg.add_input_int(label="variations", width=60, default_value=4, min_value=1, min_clamped=True, tag= "variation1")
        dpg.add_input_int(label="Tracks:", width=60, default_value=4, min_value=1, min_clamped=True, tag= "tracksnum1")
        dpg.add_slider_float(label="Duration",width = 100, tag= "duration1", max_value=20.0)
    dpg.add_button(label="Add Sounds", callback=add_sound, tag=add_sounds_button_id)
    dpg.add_button(label="Create", callback=create_project)

dpg.setup_dearpygui()
dpg.show_viewport()
dpg.start_dearpygui()

    
dpg.destroy_context()