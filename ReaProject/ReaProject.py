from reathon.nodes import *

project = Project()
track = Track()
track.name = "reaper Test"
project.add(track)
project.add_region(1,1.0,2.0,"test")
# project.add_region(4,3.0,4.0,"test2")

# project.props = [
#     ["RENDER_FILE", "Bounces"],
#   ["RENDER_PATTERN", "test\$title_$region\$title_$region"]
# ]
project.write("testrender6.rpp")


# Ideas
# Generate tracks and regions setup with user input for track number and sound variations
# Program to create reaper projects - could involve folder structure 
# We can add tracks regions, items, pre render
# Display preselected events for