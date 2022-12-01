---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 16/11/2022 07:20
---

local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')
local M28Map = import('/mods/M28AI/lua/AI/M28Map.lua')
local M28Profiling = import('/mods/M28AI/lua/AI/M28Profiling.lua')
local M28UnitInfo = import('/mods/M28AI/lua/AI/M28UnitInfo.lua')



bInitialSetup = false


function BrainCreated(aiBrain)
    local bDebugMessages = false if M28Profiling.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'BrainCreated'
    M28Profiling.FunctionProfiler(sFunctionRef, M28Profiling.refProfilerStart)

    if bDebugMessages == true then LOG(sFunctionRef..': M28 Brain has just been created for aiBrain '..aiBrain.Nickname..'; Index='..aiBrain:GetArmyIndex()) end
    if not(bInitialSetup) then
        bInitialSetup = true
        _G.repru = rawget(_G, 'repru') or repr --With thanks to Balthazar for suggesting this for where e.g. FAF develop has a function that isnt yet in FAF main
        if bDebugMessages == true then LOG(sFunctionRef..': About to do one-off setup for all brains') end
        ForkThread(M28Map.SetupMap)
    end

    ForkThread(OverseerManager, aiBrain)

    M28Profiling.FunctionProfiler(sFunctionRef, M28Profiling.refProfilerEnd)

end

function TestCustom(aiBrain)
    --Check for sparky and how many orders it has
    local tOurSparkies = aiBrain:GetListOfUnits(categories.FIELDENGINEER, false, true)
    if M28Utilities.IsTableEmpty(tOurSparkies) == false then
        for iUnit, oUnit in tOurSparkies do
            local tQueue = oUnit:GetCommandQueue()
            LOG('Considering sparky '..oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit)..': About to list out command queue details. Is queue empty='..tostring(M28Utilities.IsTableEmpty(tQueue)))

            if M28Utilities.IsTableEmpty(tQueue) == false then
                LOG('Total commands='..table.getn(tQueue))
                for iCommand, tOrder in ipairs(tQueue) do
                    LOG('iCommand='..iCommand..'; tOrder='..repru(tOrder)..'; position='..repru(tOrder.position)..'; Type='..repru(tOrder.type))
                end
            end
        end
    end
end

function OverseerManager(aiBrain)
    while (GetGameTimeSeconds() <= 4.5) do
        WaitTicks(1)
    end
    while not(aiBrain:IsDefeated()) and not(aiBrain.M28IsDefeated) do
        TestCustom(aiBrain)
        WaitSeconds(1)
    end
end