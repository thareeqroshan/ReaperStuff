# tRoshan Scripts

[![check](https://github.com/thareeqroshan/ReaperStuff/actions/workflows/check.yml/badge.svg)](https://github.com/thareeqroshan/ReaperStuff/actions/workflows/check.yml)

REAPER scripts for game audio and sound design work, distributed via ReaPack.

## Installation

In REAPER, go to **Extensions > ReaPack > Import repositories** and paste this URL:

```
https://github.com/thareeqroshan/ReaperStuff/raw/master/index.xml
```

Then install what you want from **Extensions > ReaPack > Browse packages**.

## Packages

| Package | What it does |
| --- | --- |
| Track Navigation | Eight actions to select, extend and shrink the track selection, skipping hidden tracks |
| Select only direct children | Replaces the track selection with the immediate children of the selected tracks |
| Video Scene Detect | Detects scene cuts in the selected video item and creates markers or regions |
| Create New Sound | Sets up an sfx session for game audio |
| Randomise Take Files by Group | Groups selected items by asset name and swaps the active take source |
| Item Properties Randomizer | Randomises properties across the selected items |
| Rename Selected Regions | Includes region and track renaming actions with prefix, suffix, literal find/replace, full-name replacement, numbering, and a live preview |
| Create Regions From Selected Items | Creates one region per selected item with take or track naming, a colour picker, and track or parent render routing |
| Create Folder From Selected Tracks | Wraps the selected tracks in a folder |
| Create Four Child Tracks | Turns each selected track into a folder with four new children and moves its media items to the first child |
| Copy FX parameters from the last focused FX | Copies the last focused FX's parameters |
| Paste FX parameters to the last focused FX | Applies previously copied parameters to the last focused FX |
| Pan item 10 units to the left / right | Pans the selected items and shows the take pan envelope |

## Requirements

REAPER 7. Most scripts need nothing else — these are the exceptions:

| Requirement | Needed by |
| --- | --- |
| [ReaImGui](https://github.com/cfillion/reaimgui) | Video Scene Detect, Randomise Take Files by Group, Item Properties Randomizer, Rename Selected Regions / Tracks, Create Regions From Selected Items |
| [PySceneDetect](https://www.scenedetect.com/) ([CLI reference](https://www.scenedetect.com/cli/)) | Video Scene Detect |
| js_ReaScriptAPI *(optional)* | Track Navigation, only for scroll-into-view |

ReaImGui and js_ReaScriptAPI both install through ReaPack. For PySceneDetect, use the
[Windows installer](https://www.scenedetect.com/download/) (no Python needed) or, if you already
have Python, `pip install --upgrade scenedetect`.

## Creating a parent folder

Select adjacent tracks or folders at the level you want to wrap, under the same existing
parent. Selecting a folder includes its entire existing subtree; its children do not need
to be individually selected. Nested folders and closing depths are preserved, including
when the final selected track is itself a folder parent.

Unselected sibling gaps, selections crossing an existing parent's boundary, and folders
without a closing track are rejected with a message before anything changes. No tracks are
moved, and unrelated tracks retain their existing folder membership.

## Create Four Child Tracks

Select one or more non-folder tracks and run **tRoshan_Create_Four_Child_Tracks.lua**.
Each selected track becomes a folder with four new child tracks directly beneath it.
Its media items move to the first child without changing their timeline positions;
the other three children contain no media items. FX and track settings stay on the parent.

If any selected track is already a folder, the entire action is rejected before anything
changes. Existing surrounding folder boundaries are preserved, including when a selected
track closes one or more folders. The entire batch is one undo step.

## FX parameter copy/paste

The copy and paste actions support regular-track, master-track, and take FX, including
non-active takes, input/monitoring FX, and individual plug-ins inside containers. Focus the
intended plug-in window before running the action. REAPER can also report the last focused FX
after focus moves away while its window remains open. Whole containers are not copied:
focus the individual plug-in instead.

Paste requires the same plug-in identity and parameter layout (count, names, and ranges);
renaming an FX instance does not change its identity. Invalid or incompatible clipboard data
is rejected before any parameters change. A failed copy keeps the previous clipboard.
Only parameter values are copied, not a plug-in's full preset/state.

Update both actions to version 1.1 or later and make a fresh copy after upgrading. Older
clipboard contents lack the metadata needed for safe compatibility checks. The actions
remain independently installable ReaPack packages with no shared helper dependency, and the
clipboard lasts only for the current REAPER session.

## Rename Selected Regions and Tracks

Install or update **Rename Selected Regions** through ReaPack. Version 1.1 also includes
**Rename Selected Tracks** and the shared dialog helper; no separate package is required.
Both actions use paired Find/Replace and Prefix/Suffix fields, optional numbering controls,
and a preview that expands with the window. Unchanged preview names are dimmed.

Select tracks and run **tRoshan_Rename_Selected_Tracks.lua** to rename them in top-to-bottom
track order. Only selected regular tracks are renamed. Media items, FX, routing, and folder
structure stay intact; the Master track is excluded.

The region action requires a recent REAPER build exposing the native region selection APIs
(`GetRegionOrMarker`, `GetRegionOrMarkerInfo_Value`, and `GetSetRegionOrMarkerInfo_String`).
Older builds show an update prompt instead of renaming a different selection.

Select regions in REAPER, run **tRoshan_Rename_Selected_Regions.lua**, review the preview,
then click **Apply**. The preview follows the current region selection in the active project;
markers and unselected regions are never renamed. A time selection alone does not select regions.

Operations run in this order: optional full-name replacement, case-sensitive literal find/replace,
prefix, optional numbering, suffix. An empty Find field skips replacement; an empty Replace with
field removes matches. Region numbering follows timeline order (internal order breaks ties);
track numbering follows track order. Both have a configurable start, minimum digit count, and
separator. Blank resulting names are allowed. Each Apply is one undo step. Apply again to
repeat the operations on the current names; Reset clears the controls without changing names.
The preview follows the current selection in the active project. Region IDs, positions, and
colours stay intact.

## Create Regions From Selected Items

Select media items and run **tRoshan_Create_Regions_From_Selected_Items.lua**. Choose active take
names or item track names, pick a colour, and choose the item track or its immediate folder parent
as the Region Render Matrix destination. A top-level track uses Master as its parent destination.
This changes region render assignments, not track sends or audio routing.

The preview follows the selected items in the active project. **Create regions** creates one region
spanning each item's exact bounds, including overlapping items, and closes the window. Existing
regions are left untouched. The entire batch is one undo step. Missing active takes block creation
in take-name mode; track-name mode also supports empty items. Items with no positive duration block
creation in either mode. Names are used as-is, including file extensions and blank names.

## Development

`index.xml` is generated by [reapack-index](https://github.com/cfillion/reapack-index) in GitHub
Actions. **Do not edit it by hand** — your changes will be overwritten.

To release a change: edit the script, bump `* Version:` in its header, then commit and push to
`master`. The `deploy` workflow regenerates `index.xml` and commits it. Package metadata
(version, description, changelog, bundled files) all lives in the script headers — see the
[packaging documentation](https://github.com/cfillion/reapack-index/wiki/Packaging-Documentation).

`deploy` also uploads `index.xml` to the `index` release, so it can be downloaded from
`https://github.com/thareeqroshan/ReaperStuff/releases/download/index/index.xml`. The original
`raw/master/index.xml` link still works. GitHub can temporarily serve an older copy from either
link, so a successful deploy does not guarantee immediate visibility in ReaPack.

Packages that ship several scripts use a `@metapackage` file listing them under `@provides`; see
[Track Navigation](ReaScripts/Track%20Navigation/tRoshan_Track%20Navigation.lua). Every file
bundled that way needs `@noindex` so it isn't also published as a standalone package.

To validate locally before pushing (optional, needs Ruby):

```
bundle install
bundle exec reapack-index --check --ignore vendor/bundle
```

Both workflows use `.github/actions/setup-reapack` to cache the gems pinned in `Gemfile.lock`.
An exact cache hit skips Bundler installation and configures it through environment variables;
the key includes the lockfile, Ruby version, OS version and architecture. On a miss, Bundler
installs the missing gems, including compiling `rugged` (libgit2), which can take over a minute.
The previous setup-ruby cache is reused when available to avoid rebuilding during migration.
GitHub evicts caches unused for 7 days, so `check` runs twice a week on `master` to keep it warm.
To upgrade reapack-index, run `bundle update reapack-index` and commit the new `Gemfile.lock`.

Focused folder, FX, and region regressions use a small mocked REAPER API and Lua 5.4, without opening
or changing a live REAPER project. From the repository root on Windows, run:

```
lua tests\reascript_regressions.lua
```

Append `folder`, `FX`, or `Regions` to run only that group. The mocks cover hierarchy/routing boundaries,
FX target dispatch, clipboard compatibility, region creation and render assignments, and failure handling; they do not replace
testing plug-in behavior inside REAPER.

## Licence

GPL v3 unless a script header states otherwise.
