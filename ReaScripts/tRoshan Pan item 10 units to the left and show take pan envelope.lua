function Msg(value)
    console = true
    if console then
        reaper.ShowConsoleMsg(tostring(value) .. "\n")
    end
end

-- Get selected items and return as an array

function getSelectedItems()
    local items = {}
    local itemCount = reaper.CountSelectedMediaItems(0)
    for i = 0, itemCount - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        items[i] = item
    end
    return {itemCount, items}
end

-- function to check if a mediaitem has pan take envelope
function hasPanTakeEnvelope(item)
    local take = reaper.GetActiveTake(item)
    local takeEnvelope = reaper.GetTakeEnvelopeByName(take, "PAN")
    if takeEnvelope ~= nil then
        return true
    else
        return false
    end
end

-- function to create pan take envelope
function createPanTakeEnvelope(item)
    local take = reaper.GetActiveTake(item)
    local takeEnvelope = reaper.GetTakeEnvelopeByName(take, "Pan")
    -- if takeEnvelope == nil then
    --     reaper.InsertTakeEnvelopePoint(take, -1, 0, 0, 0, 0, true)
    --     reaper.InsertTakeEnvelopePoint(take, -1, 1, 0, 0, 0, true)
    --     reaper.Envelope_SortPoints(takeEnvelope)
    -- end
    return takeEnvelope
end


function shiftTakePan(item, shift)
    -- get all the points in the take pan envelope and shift them by shift
    local take = reaper.GetActiveTake(item)
    local takeEnvelope = reaper.GetTakeEnvelopeByName(take, "Pan")
    local pointCount = reaper.CountEnvelopePoints(takeEnvelope)
    for i = 0, pointCount - 1 do
        local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(takeEnvelope, i)
        -- clamp the pan value to -1 and 1
        new_value = value + shift
        if value + shift > 1 then
            new_value = 1
        end
            
        reaper.SetEnvelopePoint(takeEnvelope, i, time, new_value, shape, tension, selected, true)
    end
end



data = getSelectedItems()
itemCount = data[1]
items = data[2]
-- Msg(itemCount)
-- Msg(createPanTakeEnvelope(items[0]))

reaper.Main_OnCommandEx(reaper.NamedCommandLookup("_S&M_TAKEENV2"), 0 )

for i = 0, itemCount - 1 do
    shiftTakePan(items[i], 0.1)
end

