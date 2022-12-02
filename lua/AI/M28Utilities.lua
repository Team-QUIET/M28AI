---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 16/11/2022 07:26
---
local M28Profiling = import('/mods/M28AI/lua/AI/M28Profiling.lua')
local NavUtils = import("/lua/sim/navutils.lua")

tErrorCountByMessage = {} --WHenever we have an error, then the error message is a key that gets included in this table

bM28AIInGame = false --true if have M28 AI in the game (used to avoid considering callback logic further)


function ErrorHandler(sErrorMessage, bWarningNotError)
    --Intended to be put in code wherever a condition isn't met that should be, so can debug it without the code crashing
    --Search for "error " in the log to find both these errors and normal lua errors, while not bringing up warnings
    if sErrorMessage == nil then sErrorMessage = 'Not specified' end
    local iCount = (tErrorCountByMessage[sErrorMessage] or 0) + 1
    tErrorCountByMessage[sErrorMessage] = iCount
    local iInterval = 1
    local bShowError = true
    if iCount > 3 then
        bShowError = false
        if iCount > 2187 then iInterval = 2187
        elseif iCount > 729 then iInterval = 729
        elseif iCount > 243 then iInterval = 243
        elseif iCount >= 81 then iInterval = 81
        elseif iCount >= 27 then iInterval = 27
        elseif iCount >= 9 then iInterval = 9
        else iInterval = 3
        end
        if math.floor(iCount / iInterval) == iCount/iInterval then bShowError = true end
    end
    if bShowError then
        local sErrorBase = 'M28ERROR '
        if bWarningNotError then sErrorBase = 'M28WARNING: ' end
        sErrorBase = sErrorBase..'Count='..iCount..': GameTime '..math.floor(GetGameTimeSeconds())..': '
        sErrorMessage = sErrorBase..sErrorMessage
        local a, s = pcall(assert, false, sErrorMessage)
        WARN(a, s)
    end

    --if iOptionalWaitInSeconds then WaitSeconds(iOptionalWaitInSeconds) end
end

function ErrorHandler(sErrorMessage, bWarningNotError)
    --Intended to be put in code wherever a condition isn't met that should be, so can debug it without the code crashing
    --Search for "error " in the log to find both these errors and normal lua errors, while not bringing up warnings
    if sErrorMessage == nil then sErrorMessage = 'Not specified' end
    local iCount = (tErrorCountByMessage[sErrorMessage] or 0) + 1
    tErrorCountByMessage[sErrorMessage] = iCount
    local iInterval = 1
    local bShowError = true
    if iCount > 3 then
        bShowError = false
        if iCount > 2187 then iInterval = 2187
        elseif iCount > 729 then iInterval = 729
        elseif iCount > 243 then iInterval = 243
        elseif iCount >= 81 then iInterval = 81
        elseif iCount >= 27 then iInterval = 27
        elseif iCount >= 9 then iInterval = 9
        else iInterval = 3
        end
        if math.floor(iCount / iInterval) == iCount/iInterval then bShowError = true end
    end
    if bShowError then
        local sErrorBase = 'M28ERROR '
        if bWarningNotError then sErrorBase = 'M28WARNING: ' end
        sErrorBase = sErrorBase..'Count='..iCount..': GameTime '..math.floor(GetGameTimeSeconds())..': '
        sErrorMessage = sErrorBase..sErrorMessage
        local a, s = pcall(assert, false, sErrorMessage)
        WARN(a, s)
    end

    --if iOptionalWaitInSeconds then WaitSeconds(iOptionalWaitInSeconds) end
end

function IsTableEmpty(tTable, bEmptyIfNonTableWithValue)
    --bEmptyIfNonTableWithValue - Optional, defaults to true
    --E.g. if passed oUnit to a function that was expecting a table, then setting bEmptyIfNonTableWithValue = false means it will register the table isn't nil

    if (type(tTable) == "table") then
        if next (tTable) == nil then return true
        else
            for i1, v1 in pairs(tTable) do
                if IsTableEmpty(v1, false) == false then return false end
            end
            return true
        end
    else
        if tTable == nil then return true
        else
            if bEmptyIfNonTableWithValue == nil then return true
            else return bEmptyIfNonTableWithValue
            end
        end

    end
end

function ForkedDrawRectangle(rRect, iColour, iDisplayCount)
    --Only call via cork thread
    --Draws lines around rRect; rRect should be a rect table, with keys x0, x1, y0, y1
    --iColour - if it isn't a number from 1 to 8 then it will try and use the value as the hex key instead

    local bDebugMessages = false if M28Profiling.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'ForkedDrawRectangle'
    if bDebugMessages == true then LOG(sFunctionRef..': rRect='..repru(rRect)) end

    local sColour
    if iColour == nil then sColour = 'c00000FF' --dark blue
    elseif iColour == 1 then sColour = 'c00000FF' --dark blue
    elseif iColour == 2 then sColour = 'ffFF4040' --Red
    elseif iColour == 3 then sColour = 'c0000000' --Black (can be hard to see on some maps)
    elseif iColour == 4 then sColour = 'fff4a460' --Gold
    elseif iColour == 5 then sColour = 'ff27408b' --Light Blue
    elseif iColour == 6 then sColour = 'ff1e90ff' --Cyan (might actually be white as well?)
    elseif iColour == 7 then sColour = 'ffffffff' --white
    elseif iColour == 8 then sColour = 'ffFF6060' --Orangy pink
    else sColour = iColour
    end


    if iDisplayCount == nil then iDisplayCount = 500
    elseif iDisplayCount <= 0 then iDisplayCount = 1
    elseif iDisplayCount >= 10000 then iDisplayCount = 10000 end
    local tCurPos, tLastPos
    local iCurX, iCurZ

    local iCurDrawCount = 0
    local iCount = 0
    while true do
    iCount = iCount + 1
    if iCount > 10000 then ErrorHandler('Infinite loop') break end
    for iValX = 1, 2 do
    for iValZ = 1, 2 do
    if iValX == 1 then
    iCurX = rRect['x0']
    if iValZ == 1 then iCurZ = rRect['y0'] else iCurZ = rRect['y1'] end
    else
    iCurX = rRect['x1']
    if iValZ == 1 then iCurZ = rRect['y1'] else iCurZ = rRect['y0'] end
    end

    tLastPos = tCurPos
    tCurPos = {iCurX, GetTerrainHeight(iCurX, iCurZ), iCurZ}
    if tLastPos then
    if bDebugMessages == true then LOG(sFunctionRef..': tLastPos='..repru(tLastPos)..'; tCurPos='..repru(tCurPos)) end
    DrawLine(tLastPos, tCurPos, sColour)
    end
    end
    end
    iCurDrawCount = iCurDrawCount + 1
    if iCurDrawCount > iDisplayCount then return end
        coroutine.yield(2) --Any more and lines will flash instead of being constant
        end
end

function DrawRectangle(rRectangle, iOptionalColour, iOptionalTimeInTicks, iOptionalSizeIncrease)
    local iRadiusIncrease = (iOptionalSizeIncrease or 0) * 0.5
    LOG('reprs of rRectangle='..reprs(rRectangle))
    LOG('x0='..rRectangle['x0'])
    ForkThread(ForkedDrawRectangle, Rect(rRectangle['x0'] - iRadiusIncrease, rRectangle['y0'] - iRadiusIncrease, rRectangle['x1'] + iRadiusIncrease, rRectangle['y1'] + iRadiusIncrease), (iOptionalColour or 1), (iOptionalTimeInTicks or 200))
end

function DrawLocation(tLocation, iOptionalColour, iOptionalTimeInTicks, iOptionalSize)
    local iRadius = (iOptionalSize or 1) * 0.5
    ForkThread(ForkedDrawRectangle, Rect(tLocation[1] - iRadius, tLocation[3] - iRadius, tLocation[1] + iRadius, tLocation[3] + iRadius), (iOptionalColour or 1), (iOptionalTimeInTicks or 200))
end

function ForkedDrawLine(tStart, tEnd, iColour, iDisplayCount)
    local bDebugMessages = false if M28Profiling.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'ForkedDrawLine'
    if bDebugMessages == true then LOG(sFunctionRef..': rRect='..repru(rRect)) end

    local sColour
    if iColour == nil then sColour = 'c00000FF' --dark blue
    elseif iColour == 1 then sColour = 'c00000FF' --dark blue
    elseif iColour == 2 then sColour = 'ffFF4040' --Red
    elseif iColour == 3 then sColour = 'c0000000' --Black (can be hard to see on some maps)
    elseif iColour == 4 then sColour = 'fff4a460' --Gold
    elseif iColour == 5 then sColour = 'ff27408b' --Light Blue
    elseif iColour == 6 then sColour = 'ff1e90ff' --Cyan (might actually be white as well?)
    elseif iColour == 7 then sColour = 'ffffffff' --white
    else sColour = 'ffFF6060' --Orangy pink
    end


    if iDisplayCount == nil then iDisplayCount = 500
    elseif iDisplayCount <= 0 then iDisplayCount = 1
    elseif iDisplayCount >= 10000 then iDisplayCount = 10000 end

    local iCurDrawCount = 0
    local iCount = 0
    while true do
        DrawLine(tStart, tEnd, sColour)
        iCount = iCount + 1
        if iCount > 10000 then ErrorHandler('Infinite loop') break end
        if iCurDrawCount > iDisplayCount then return end
        coroutine.yield(2) --Any more and lines will flash instead of being constant
    end
end

function DrawPath(tPath, iOptionalColour, iOptionalTimeInTicks)
    local iColour = iOptionalColour or 1
    local iDisplayCount = iOptionalTimeInTicks or 100
    local iCount = 0
    local tPrevPosition
    for iPath, tPath in tPath do
        iCount = iCount + 1
        if iCount > 1 then
            ForkThread(ForkedDrawLine, tPrevPosition, tPath, iColour, iDisplayCount)
        end
        tPrevPosition = {tPath[1], tPath[2], tPath[3]}
    end

end

function GetApproxTravelDistanceBetweenPositions(tStart, tEnd)
    --Similar to GetTravelDistanceBetweenPositions, but will only precisely calculate the distance from the start to the first point, and then rely on the base pathing distance calculation
    local tFullPath, iPathSize, iDistance = NavUtils.PathTo('Land', tStart, tEnd, nil)
    if tFullPath then
        if tFullPath[iPathSize][1] == tEnd[1] and tFullPath[iPathSize][3] == tEnd[3] then
            return iDistance + VDist2(tFullPath[1][1], tFullPath[1][3], tStart[1], tStart[3])
        else
            return iDistance + VDist2(tFullPath[1][1], tFullPath[1][3], tStart[1], tStart[3]) + VDist2(tFullPath[iPathSize][1], tFullPath[iPathSize][3])
        end
    else
        return nil
    end
end
function GetTravelDistanceBetweenPositions(tStart, tEnd)
    --Returns the distance for a land unit to move from tStart to tEnd using Jips pathing algorithm
    --Returns nil if cant path there

    --4th argument could be NavUtils.PathToDefaultOptions(), e.g. local tFullPath, iPathSize, iDistance = NavUtils.PathTo('Land', tStart, tEnd, NavUtils.PathToDefaultOptions()); left as nil:
    local tFullPath, iPathSize, iDistance = NavUtils.PathTo('Land', tStart, tEnd, nil)
    if tFullPath then

        --Option 1 - recalculate all distances (during testing as at 2022-11-20 sometimes even if go with option 2 below the distance is significantly lower than option 1 gives:
        local iTravelDistance = 0
        tFullPath[0] = tStart
        tFullPath[iPathSize + 1] = tEnd
        for iPath = 1, iPathSize + 1 do
            --iTravelDistance = iTravelDistance + GetDistanceBetweenPositions(tFullPath[iPath - 1], tFullPath[iPath])
            iTravelDistance = iTravelDistance + VDist2(tFullPath[iPath - 1][1], tFullPath[iPath - 1][3], tFullPath[iPath][1], tFullPath[iPath][3])
        end
        return iTravelDistance


        --[[
        --Below log is for debug
        local iDistanceAddingStartAndEnd = iDistance + VDist2(tStart[1], tStart[3], tFullPath[1][1], tFullPath[1][3]) + VDist2(tEnd[1], tEnd[3], tFullPath[iPathSize][1], tFullPath[iPathSize][3])
        if iTravelDistance > iDistanceAddingStartAndEnd then
            LOG('Just got pathing distance, iDistanceAddingStartAndEnd='..iDistanceAddingStartAndEnd..'; iTravelDistance='..iTravelDistance..'; base distance value before adjust='..iDistance..' from '..repru(tStart)..' to '..repru(tEnd)..'; iPathSize='..(iPathSize or 'nil')..'; Reprs of path='..reprs(tFullPath)..'; Distance in straight line from start to first point in path='..GetDistanceBetweenPositions(tStart, tFullPath[1])..'; Dist from last path point to end='..GetDistanceBetweenPositions(tFullPath[iPathSize], tEnd)..'; Distance if take iDistance+this='..(iDistance + GetDistanceBetweenPositions(tStart, tFullPath[1]) + GetDistanceBetweenPositions(tFullPath[iPathSize], tEnd)))
        end
        --Option 2 - just add in the first and last distance to the distance determined by the pathing algorithm:
        return iDistance + VDist2(tStart[1], tStart[3], tFullPath[1][1], tFullPath[1][3]) + VDist2(tEnd[1], tEnd[3], tFullPath[iPathSize][1], tFullPath[iPathSize][3])--]]
    else
        return nil
    end
end
function GetDistanceBetweenPositions(tPosition1, tPosition2)
    --Done for convenience and to reduce risk of human error if were to use vdist2 directly; returns the distance in a straight line (ignoring pathing) between 2 positions
    return VDist2(tPosition1[1], tPosition1[3], tPosition2[1], tPosition2[3])
end

function GenerateUniqueColourTable(iTableSize)
    local FAFColour = import("/lua/shared/color.lua")
    local tColourTable = {}
    local tInterval = {{0.13, 0.23, 0.37}, {0.13,0.37,0.23},{0.23,0.13,.37},{0.23,0.37,0.13},{0.37,0.13,0.23},{0.37,0.23,0.13}}
    local tiIntervalToUse = tInterval[math.random(table.getn(tInterval))]
    local iCurR = 0
    local iCurG = 0
    local iCurB = 0
    for iEntry = 1, iTableSize do
        iCurR = iCurR + tiIntervalToUse[1]
        if iCurR > 1 then iCurR = iCurR - 1 end
        iCurG = iCurG + tiIntervalToUse[2]
        if iCurG > 1 then iCurG = iCurG - 1 end
        iCurB = iCurB + tiIntervalToUse[3]
        if iCurB > 1 then iCurB = iCurB - 1 end
        tColourTable[iEntry] = FAFColour.ColorRGB(iCurR, iCurG, iCurB, nil)
    end
    return tColourTable

end