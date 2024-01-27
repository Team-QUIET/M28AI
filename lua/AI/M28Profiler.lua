---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 16/11/2022 07:28
---
local M28Config = import('/mods/M28AI/lua/M28Config.lua')
local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')


--Profiling variables
bGlobalDebugOverride = false --will turn debugmessages to true for all functions (where has been enabled)
bFunctionCallDebugOverride = false --use to turn on logs for when functions are entered or exited
bActiveProfiler = false --true if profiler is running
refiLastSystemTimeRecorded = 'M28ProfilerLastSystemTime' --Used for simple profiler to just measure how long something is taking without all the logs

refProfilerStart = 0
refProfilerEnd = 1

tProfilerTimeTakenInTickByFunction = {}
tProfilerTimeTakenCumulative = {}
tProfilerStartCount = {}
tProfilerEndCount = {}
tProfilerFunctionStart = {}
tProfilerTimeTakenByCount = {}
tProfilerCumulativeTimeTakenInTick = {}
tProfilerActualTimeTakenInTick = {}
sProfilerActiveFunctionForThisTick = 'nil'
refiLongestTickAfterStartRef = 0
refiLongestTickAfterStartTime = 0
bFullOutputAlreadyDone = {} -- true if have done the full output for the nth time; n being based on how long an interval we want
iFullOutputIntervalInTicks = 30 --every second (will do a full output of every log every 10s, this will just do every 30 functions)
iFullOutputCount = 0 --increased each time do a full output
iFullOutputFunctionCap = 100 --Will list the top x functions when doing full output if this is specified; set to -1 if dont want any limit
iFullOutputCycleCount = 0 --Increased each time do a full output, and reset to 0 when reach
tProfilerCountByTickByFunction = {}
tbProfilerOutputGivenForTick = {} --true if already given output for [iTick]

tFunctionCallByName = {}
iFunctionCurCount = 0

tiProfilerStartCountByFunction = {} --[functionref] - Used if want to temporarily check how many times a function is called - have this update in the function itself, along with the end count
--example of usage of the above: --M28Utilities.tiProfilerStartCountByFunction[sFunctionRef] = (M28Utilities.tiProfilerStartCountByFunction[sFunctionRef] or 0) + 1 LOG(sFunctionRef..': M28Utilities.tiProfilerStartCountByFunction[sFunctionRef]='..M28Utilities.tiProfilerStartCountByFunction[sFunctionRef])
tiProfilerEndCountByFunction = {} --[functionref] - Used if want to temporarily check how many times a function is called - have this update in the function itself, along with the end count
--Example of usage of the above: M28Utilities.tiProfilerEndCountByFunction[sFunctionRef] = (M28Utilities.tiProfilerEndCountByFunction[sFunctionRef] or 0) + 1 LOG(sFunctionRef..': M28Utilities.tiProfilerEndCountByFunction[sFunctionRef]='..M28Utilities.tiProfilerEndCountByFunction[sFunctionRef])
tMemoryOverloadTable = {} --If want to test high memory usage
iMemoryOverloadCurFactor = 0 --To avoid rerunning exact same logic
iMemoryCycleCount = 1000
bActiveMemoryProfiler = false

function FunctionProfiler(sFunctionRef, sStartOrEndRef)
    --sStartOrEndRef: refProfilerStart or refProfilerEnd (0 or 1)
    local bDebugMessages = false if bGlobalDebugOverride == true or bFunctionCallDebugOverride then   bDebugMessages = true end
    if bDebugMessages == true then LOG('FunctionProfiler: Function '..sFunctionRef..'; sStartOrEndRef='..sStartOrEndRef) end
    if M28Config.M28RunProfiling then

        if sStartOrEndRef == refProfilerStart then
            --First ever time calling:
            --1-off for any function - already done via global variables above

            --1-off for this function
            if not(tProfilerStartCount[sFunctionRef]) then
                tProfilerStartCount[sFunctionRef] = 0
                tProfilerEndCount[sFunctionRef] = 0
                tProfilerFunctionStart[sFunctionRef] = {}
                tProfilerTimeTakenCumulative[sFunctionRef] = 0
                tProfilerTimeTakenByCount[sFunctionRef] = {}
            end

            --1-off for this tick
            local iGameTimeInTicks = math.floor(GetGameTimeSeconds()*10)
            if tProfilerTimeTakenInTickByFunction[iGameTimeInTicks] == nil then
                --if bDebugMessages == true then LOG('FunctionProfiler: '..sFunctionRef..': '..iGameTimeInTicks..': Resetting active profiler') end
                tProfilerTimeTakenInTickByFunction[iGameTimeInTicks] = {}
                tProfilerCumulativeTimeTakenInTick[iGameTimeInTicks] = 0
                sProfilerActiveFunctionForThisTick = 'nil'
                tProfilerCountByTickByFunction[iGameTimeInTicks] = {}
            end

            --Increase unique count
            local iCount = tProfilerStartCount[sFunctionRef] + 1
            tProfilerStartCount[sFunctionRef] = iCount
            tProfilerFunctionStart[sFunctionRef][iCount] = GetSystemTimeSecondsOnlyForProfileUse()
            if sProfilerActiveFunctionForThisTick == 'nil' then sProfilerActiveFunctionForThisTick = sFunctionRef end
            if tProfilerCountByTickByFunction[iGameTimeInTicks][sFunctionRef] == nil then tProfilerCountByTickByFunction[iGameTimeInTicks][sFunctionRef] = 0 end
            tProfilerCountByTickByFunction[iGameTimeInTicks][sFunctionRef] = tProfilerCountByTickByFunction[iGameTimeInTicks][sFunctionRef] + 1
            --if bDebugMessages == true then LOG('FunctionProfiler: '..sFunctionRef..': refProfilerStart; iCount='..iCount..'; iGameTimeInTicks='..iGameTimeInTicks..'; System time at start='..GetSystemTimeSecondsOnlyForProfileUse()..'; tProfilerFunctionStart[sFunctionRef][iCount]='..tProfilerFunctionStart[sFunctionRef][iCount]) end

        elseif sStartOrEndRef == refProfilerEnd then
            if tProfilerStartCount[sFunctionRef] then --needed to support e.g. running this part-way through the game
                tProfilerEndCount[sFunctionRef] = (tProfilerEndCount[sFunctionRef] or 0) + 1
                local iCount = tProfilerEndCount[sFunctionRef]
                local iGameTimeInTicks = math.floor(GetGameTimeSeconds()*10)
                if tProfilerFunctionStart[sFunctionRef][iCount] == nil then
                    M28Utilities.ErrorHandler('Didnt record a start for this count.  Will assume the start time was equal to the previous count, and will increase the start count by 1 to try and align.  sFunctionRef='..sFunctionRef..'; iGameTimeInTicks='..iGameTimeInTicks..'; iCount='..(iCount or 'nil'))
                    if not(tProfilerFunctionStart[sFunctionRef]) then tProfilerFunctionStart[sFunctionRef] = {} end
                    if iCount > 1 then
                        for iAdjust = 1, (iCount - 1), 1 do
                            if tProfilerFunctionStart[sFunctionRef][iCount - iAdjust] then
                                tProfilerFunctionStart[sFunctionRef][iCount] = tProfilerFunctionStart[sFunctionRef][iCount - iAdjust]
                                break
                            end
                        end
                    end
                    if not(tProfilerFunctionStart[sFunctionRef][iCount]) then
                        tProfilerFunctionStart[sFunctionRef][iCount] = 0
                    end
                    tProfilerStartCount[sFunctionRef] = iCount
                end
                local iCurTimeTaken = GetSystemTimeSecondsOnlyForProfileUse() - tProfilerFunctionStart[sFunctionRef][iCount]

                if M28Config.M28ProfilerIgnoreFirst2Seconds and iGameTimeInTicks <= 20 then iCurTimeTaken = 0 end
                --if bDebugMessages == true then LOG('FunctionProfiler: '..sFunctionRef..': refProfilerEnd; iCount='..iCount..'; iCurTimeTaken='..iCurTimeTaken..'; tProfilerFunctionStart[sFunctionRef][iCount]='..tProfilerFunctionStart[sFunctionRef][iCount]) end
                if not(tProfilerTimeTakenCumulative[sFunctionRef]) then tProfilerTimeTakenCumulative[sFunctionRef] = 0 end
                tProfilerTimeTakenCumulative[sFunctionRef] = tProfilerTimeTakenCumulative[sFunctionRef] + iCurTimeTaken
                tProfilerTimeTakenByCount[sFunctionRef][iCount] = iCurTimeTaken


                if not(tProfilerTimeTakenInTickByFunction[iGameTimeInTicks]) then
                    tProfilerTimeTakenInTickByFunction[iGameTimeInTicks] = {}
                    tProfilerCumulativeTimeTakenInTick[iGameTimeInTicks] = 0
                    tProfilerCountByTickByFunction[iGameTimeInTicks] = {}
                end

                if not(tProfilerTimeTakenInTickByFunction[iGameTimeInTicks][sFunctionRef]) then tProfilerTimeTakenInTickByFunction[iGameTimeInTicks][sFunctionRef] = 0 end

                tProfilerTimeTakenInTickByFunction[iGameTimeInTicks][sFunctionRef] = tProfilerTimeTakenInTickByFunction[iGameTimeInTicks][sFunctionRef] + iCurTimeTaken

                --if bDebugMessages == true then LOG('FunctionProfiler: iGameTimeInTicks='..iGameTimeInTicks..'; sFunctionRef='..sFunctionRef..'; sProfilerActiveFunctionForThisTick='..sProfilerActiveFunctionForThisTick) end
                if sFunctionRef == sProfilerActiveFunctionForThisTick or sProfilerActiveFunctionForThisTick == 'nil' then
                    tProfilerCumulativeTimeTakenInTick[iGameTimeInTicks] = tProfilerCumulativeTimeTakenInTick[iGameTimeInTicks] + iCurTimeTaken
                    --if bDebugMessages == true then LOG('FunctionProfiler: iGameTimeInTicks='..iGameTimeInTicks..'; Clearing active function from profiler; iCurTimeTaken='..iCurTimeTaken..'; tProfilerCumulativeTimeTakenInTick[iGameTimeInTicks]='..tProfilerCumulativeTimeTakenInTick[iGameTimeInTicks]) end
                    sProfilerActiveFunctionForThisTick = 'nil'
                end

                --Track longest tick (ignore first min due to mapping initialisation)
                if iGameTimeInTicks > 600 then
                    if iCurTimeTaken > refiLongestTickAfterStartTime then
                        refiLongestTickAfterStartTime = iCurTimeTaken
                        refiLongestTickAfterStartRef = iGameTimeInTicks
                    end
                end
            end

        else ErrorHandler('FunctionProfiler: Unknown reference, wont record')
        end
    end
end

function ProfilerActualTimePerTick()
    if M28Config.M28RunProfiling and not(bActiveProfiler) then
        bActiveProfiler = true
        local iGameTimeInTicks
        local iPrevGameTime = 0
        local iSystemTime = 0
        while true do
            iPrevGameTime = GetSystemTimeSecondsOnlyForProfileUse()
            WaitTicks(1)
            iSystemTime = GetSystemTimeSecondsOnlyForProfileUse()
            iGameTimeInTicks = math.floor(GetGameTimeSeconds()*10)
            if M28Config.M28ProfilerIgnoreFirst2Seconds and iGameTimeInTicks <= 20 then
                --Dont record
            else
                tProfilerActualTimeTakenInTick[iGameTimeInTicks] = iSystemTime - iPrevGameTime
            end
            ProfilerOutput()
        end

    end
end

function ProfilerOutput()
    local sFunctionRef = 'ProfilerOutput'
    local bDebugMessages = false if bGlobalDebugOverride == true then   bDebugMessages = true end

    if M28Config.M28RunProfiling then
        local iCurTick = math.floor(GetGameTimeSeconds()*10) - 1
        if not(tbProfilerOutputGivenForTick[iCurTick]) then
            tbProfilerOutputGivenForTick[iCurTick] = true
            local bIncludePerTickLog = M28Config.M28ProfilingIncludePerTick
            if bIncludePerTickLog then
                LOG(sFunctionRef..': Tick='..iCurTick..'; Time taken='..(tProfilerCumulativeTimeTakenInTick[iCurTick] or 'nil')..'; Entire time for tick='..(tProfilerActualTimeTakenInTick[iCurTick] or 'nil')..'; About to list out top 10 functions in this tick')
                local iCount = 0
                if M28Utilities.IsTableEmpty(tProfilerTimeTakenInTickByFunction[iCurTick]) == false then
                    for sFunctionName, iValue in M28Utilities.SortTableByValue(tProfilerTimeTakenInTickByFunction[iCurTick], true) do
                        iCount = iCount + 1
                        LOG(sFunctionRef..': iTick='..iCurTick..': No.'..iCount..'='..sFunctionName..'; TimesRun='..(tProfilerCountByTickByFunction[iCurTick][sFunctionName] or 'nil')..'; Total Time='..iValue)
                        if iCount >= 10 then break end
                    end

                    LOG(sFunctionRef..': About to list top 10 called functions in this tick')
                    iCount = 0
                    for sFunctionName, iValue in M28Utilities.SortTableByValue(tProfilerCountByTickByFunction[iCurTick], true) do
                        iCount = iCount + 1
                        LOG(sFunctionRef..': iTick='..iCurTick..': No.'..iCount..'='..sFunctionName..'; TimesRun='..(tProfilerCountByTickByFunction[iCurTick][sFunctionName] or 'nil')..'; Total Time='..iValue)
                        if iCount >= 10 then break end
                    end
                end
            end
        --else
        --LOG(sFunctionRef..': Tick='..iCurTick..'; Below threshold at '..(tProfilerCumulativeTimeTakenInTick[iCurTick] or 'missing'))
        --end
        --end

            --Include full output of function cumulative time taken every interval
            local bFullOutputNow = false

            if iCurTick > (iFullOutputCount + 1) * iFullOutputIntervalInTicks then bFullOutputNow = true end
            if bFullOutputNow then
                if bFullOutputAlreadyDone[iFullOutputCount + 1] then
                    --Already done
                else
                    local bLimitFunction = false
                    local iFunctionLimit
                    if iFullOutputFunctionCap > 0 then
                        bLimitFunction = true
                        iFunctionLimit = iFullOutputFunctionCap
                    end
                    iFullOutputCount = iFullOutputCount + 1
                    bFullOutputAlreadyDone[iFullOutputCount] = true
                    LOG(sFunctionRef..': About to print detailed output of all functions cumulative values')
                    iCount = 0
                    for sFunctionName, iValue in M28Utilities.SortTableByValue(tProfilerTimeTakenCumulative, true) do
                        iCount = iCount + 1
                        if tProfilerStartCount[sFunctionName] == nil then LOG('ERROR somehow '..sFunctionName..' hasnt been recorded in the cumulative count despite having its time recorded.  iValue='..iValue)
                        else
                            LOG(sFunctionRef..': No.'..iCount..'='..sFunctionName..'; TimesRun='..tProfilerStartCount[sFunctionName]..'; Time='..iValue)
                        end
                        if bLimitFunction and iCount >= iFunctionLimit then break end
                    end
                    --Give the total time taken to get to this point based on time per tick
                    local iTotalTimeTakenToGetHere = 0
                    local iTotalDelayedTime = 0
                    local iLongestTickTime = 0
                    local iLongestTickRef
                    for iTick, iTime in tProfilerActualTimeTakenInTick do
                        iTotalTimeTakenToGetHere = iTotalTimeTakenToGetHere + iTime
                        iTotalDelayedTime = iTotalDelayedTime + math.max(0, iTime - 0.1)
                        if iTime > iLongestTickTime then
                            iLongestTickTime = iTime
                            iLongestTickRef = iTick
                        end
                    end
                    LOG(sFunctionRef..': Total time taken to get to '..iCurTick..'= '..iTotalTimeTakenToGetHere..'; Total time of any freezes = '..iTotalDelayedTime..'; Longest tick time='..iLongestTickTime..'; tick ref = '..((iLongestTickRef or 0) - 1)..' to '..(iLongestTickRef or 'nil'))

                end
            end
        end
    end
end

function OutputRecentFunctionCalls(sRef, iCycleSize)
    --NOTE: Insert below commented out code into e.g. the overseer for the second that want it.  Also can adjust the threshold for iFunctionCurCount from 10000, but if setting to 1 then only do for an individual tick or likely will crash the game
    --[[if not(bSetHook) and GetGameTimeSeconds() >= 1459 then
        bSetHook = true
        M27Utilities.bGlobalDebugOverride = true
        --debug.sethook(M27Utilities.AllFunctionHook, "c", 200)
        debug.sethook(M27Utilities.OutputRecentFunctionCalls, "c", 1)
    end--]]

    local sName = tostring(debug.getinfo(2, "n").name)
    if sName then tFunctionCallByName[sName] = (tFunctionCallByName[sName] or 0) + 1 end
    iFunctionCurCount = iFunctionCurCount + 1
    if iFunctionCurCount >= iCycleSize then
        iFunctionCurCount = 0
        LOG('Every function hook: tFunctionCallByName='..repru(tFunctionCallByName)..'; debug.traceback='..debug.traceback())
        tFunctionCallByName = {}
    end
end

function IncreaseMemoryUsage(iFactor)
    --To help debuging by generating high memory scenarios.  Examples of rough increased memory based on iFactor (very rough guides based on running once on a simple replay on flat 512 map and checking taskmanager):
    --10k = +50mb
    --20k = +110mb
    --30k = +280mb
    --40k = +360mb
    --50k = +440mb
    --100k = +836mb
    --150 = +1224mb
    if not(iMemoryOverloadCurFactor == iFactor) then
        tMemoryOverloadTable = {}
        for iLoop = 1, iFactor do
            tMemoryOverloadTable[iLoop] = { }
            for iSecondLoop = 1, 1000 do
                tMemoryOverloadTable[iLoop][iSecondLoop] = math.random(1, 100000)
            end
        end
        iMemoryOverloadCurFactor = iFactor
    end
end

function ShowFileMemoryUsage()
    local bDebugMessages = false if bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'ShowFileMemoryUsage'
    FunctionProfiler(sFunctionRef, refProfilerStart)

    if not(bActiveMemoryProfiler) then
        bActiveMemoryProfiler = true
        local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')
        local M28Map = import('/mods/M28AI/lua/AI/M28Map.lua')
        local M28Profiler = import('/mods/M28AI/lua/AI/M28Profiler.lua')
        local M28UnitInfo = import('/mods/M28AI/lua/AI/M28UnitInfo.lua')
        local M28Economy = import('/mods/M28AI/lua/AI/M28Economy.lua')
        local M28ACU = import('/mods/M28AI/lua/AI/M28ACU.lua')
        local M28Engineer = import('/mods/M28AI/lua/AI/M28Engineer.lua')
        local M28Factory = import('/mods/M28AI/lua/AI/M28Factory.lua')
        local M28Team = import('/mods/M28AI/lua/AI/M28Team.lua')
        local M28Conditions = import('/mods/M28AI/lua/AI/M28Conditions.lua')
        local M28Chat = import('/mods/M28AI/lua/AI/M28Chat.lua')
        local M28Land = import('/mods/M28AI/lua/AI/M28Land.lua')
        local M28Air = import('/mods/M28AI/lua/AI/M28Air.lua')
        local M28Orders = import('/mods/M28AI/lua/AI/M28Orders.lua')
        local M28Micro = import('/mods/M28AI/lua/AI/M28Micro.lua')
        local M28Overseer = import('/mods/M28AI/lua/AI/M28Overseer.lua')
        local M28Building = import('/mods/M28AI/lua/AI/M28Building.lua')

        local Utils = import('/lua/system/utils.lua')
        local tsFileNames = {
            ['M28ACU'] = M28ACU,
            ['M28Air'] = M28Air,
            ['M28Brain'] = import('/mods/M28AI/lua/AI/M28Brain.lua'),
            ['M28Building'] = M28Building,
            ['M28Chat'] = M28Chat,
            ['M28Conditions'] = M28Conditions,
            ['M28Economy'] = M28Economy,
            ['M28Engineer'] = M28Engineer,
            ['M28Events'] = import('/mods/M28AI/lua/AI/M28Events.lua'),
            ['M28Factory'] = M28Factory,
            ['M28Land'] = M28Land,
            ['M28Logic'] = import('/mods/M28AI/lua/AI/M28Logic.lua'),
            ['M28Map'] = M28Map,
            ['M28Micro'] = M28Micro,
            ['M28Navy'] = import('/mods/M28AI/lua/AI/M28Navy.lua'),
            ['M28Orders'] = M28Orders,
            ['M28Overseer'] = M28Overseer,
            ['M28Profiler'] = import('/mods/M28AI/lua/AI/M28Profiler.lua'),
            ['M28Team'] = M28Team,
            ['M28UnitInfo'] = M28UnitInfo,
            ['M28Utilities'] = M28Utilities,
        }
        while true do
            iMemoryCycleCount = iMemoryCycleCount + 1
            if iMemoryCycleCount >= 60 then
                --This provides the size of any global tables in a file; if wanted to, can use ToBytes to point to a specific table in that file to narrow down on ones that are large
                for sFileName, tGlobalTablesInFile in tsFileNames do
                    LOG('ToBytes for '..sFileName..'='..Utils.ToBytes(tGlobalTablesInFile))
                end
                iMemoryCycleCount = 0
            end
            FunctionProfiler(sFunctionRef, refProfilerEnd)
            WaitSeconds(1)
            FunctionProfiler(sFunctionRef, refProfilerStart)
        end
    end
    FunctionProfiler(sFunctionRef, refProfilerEnd)
end

function SpawnSetUnitsForBrain(aiBrain)
    --Done to help with profiling - spawn in specific units
    local iCategoriesToSpawn = categories.TECH3 * categories.AMPHIBIOUS + categories.EXPERIMENTAL * categories.AMPHIBIOUS + categories.TECH2 * categories.AMPHIBIOUS - categories.UNTARGETABLE
    local tsUnitsToSpawn = EntityCategoryGetUnitList(iCategoriesToSpawn)
    local M28Map = import('/mods/M28AI/lua/AI/M28Map.lua')
    local tSpawnLocationBase = M28Map.PlayerStartPoints[aiBrain:GetArmyIndex()]
    for iUnit, sUnit in tsUnitsToSpawn do
        CreateUnit(sUnit, aiBrain:GetArmyIndex(), tSpawnLocationBase[1], tSpawnLocationBase[2], tSpawnLocationBase[3], 0, 0, 0, 0, 'Air')
    end
end

function SimpleProfiler(iInterval)
    local iTimeOfLastCycle
    local iTimeAfter10s
    while true do
        iTimeOfLastCycle = GetSystemTimeSecondsOnlyForProfileUse()
        WaitSeconds(iInterval)
        if not(iTimeAfter10s) then iTimeAfter10s = GetSystemTimeSecondsOnlyForProfileUse() end
        LOG('SimpleProfiler: Time='..math.floor(GetGameTimeSeconds()*10)..'; Time taken cumulative='..GetSystemTimeSecondsOnlyForProfileUse()..'; Time since last update='..(GetSystemTimeSecondsOnlyForProfileUse() -iTimeOfLastCycle)..'; Time excl first 10s='..(GetSystemTimeSecondsOnlyForProfileUse() -iTimeAfter10s))
    end
end