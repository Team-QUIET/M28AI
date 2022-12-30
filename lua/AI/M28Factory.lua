---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 02/12/2022 22:33
---
local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')
local M28UnitInfo = import('/mods/M28AI/lua/AI/M28UnitInfo.lua')
local M28Economy = import('/mods/M28AI/lua/AI/M28Economy.lua')
local M28Map = import('/mods/M28AI/lua/AI/M28Map.lua')
local M28Orders = import('/mods/M28AI/lua/AI/M28Orders.lua')
local M28Profiler = import('/mods/M28AI/lua/AI/M28Profiler.lua')
local M28Conditions = import('/mods/M28AI/lua/AI/M28Conditions.lua')
local M28Team = import('/mods/M28AI/lua/AI/M28Team.lua')
local M28Engineer = import('/mods/M28AI/lua/AI/M28Engineer.lua')

local reftBlueprintPriorityOverride = 'M28FactoryPreferredBlueprintByCategory' --[x] is the blueprint ref, if there's a priority override it returns a numerical value (higher number = higher priority)
local refiTimeSinceLastOrderCheck = 'M28FactoryTimeSinceLastCheck' --against factory, gametime in seconds when the factory was last identified as idle with no order
--NOTE: Also have a blueprint blacklist in the landsubteam data - see M28Team

--Factory types (used by subteams)
refiFactoryTypeLand = 1
refiFactoryTypeAir = 2
refiFactoryTypeNaval = 3
refiFactoryTypeOther = 4

function GetBlueprintsThatCanBuildOfCategory(aiBrain, iCategoryCondition, oFactory, bGetSlowest, bGetFastest, bGetCheapest, iOptionalCategoryThatMustBeAbleToBuild, bIgnoreTechDifferences)
    --returns nil if cant find any blueprints that can build
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'GetBlueprintsThatCanBuildOfCategory'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local tBlueprints = EntityCategoryGetUnitList(iCategoryCondition)
    local tAllBlueprints = __blueprints
    local tValidBlueprints = {}
    local iValidBlueprints = 0
    local tBestBlueprints = {}
    local iBestBlueprints = 0
    local iHighestTech = 1
    local iCurrentTech = 1
    --if bGetSlowest == nil then bGetSlowest = false end
    --if bGetFastest == nil then bGetFastest = false end
    local iCurSpeed, iCurMass
    local tiLowestSpeedByTech = {1000, 1000, 1000}
    local tiLowestMassByTech = {100000000, 100000000, 100000000}
    local tiHighestSpeedByTech = {0,0,0}
    local oCurBlueprint
    local iHighestPriority = 0
    local bCanBuildRequiredCategory
    local iCategoriesThatBlueprintCanBuild
    local tsBlueprintsMeetingDesiredCategoriesToBuild
    if iOptionalCategoryThatMustBeAbleToBuild then
        tsBlueprintsMeetingDesiredCategoriesToBuild = EntityCategoryGetUnitList(iOptionalCategoryThatMustBeAbleToBuild)
        if bDebugMessages == true then LOG(sFunctionRef..': tsBlueprintsMeetingDesiredCategoriesToBuild='..repru(tsBlueprintsMeetingDesiredCategoriesToBuild)) end
    end





    if bDebugMessages == true then LOG(sFunctionRef..': reftBlueprintPriorityOverride='..repru(aiBrain[reftBlueprintPriorityOverride])) end
    if not(oFactory.CanBuild) then
        if oFactory.UnitId then
            M28Utilities.ErrorHandler('Factory '..oFactory.UnitId..M28UnitInfo.GetUnitLifetimeCount(oFactory)..' doesnt have .canbuild')
        else
            M28Utilities.ErrorHandler('Factory has no UnitId and doesnt have .CanBuild')
        end
        M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
        return nil
    else
        for _, sBlueprint in tBlueprints do
            if bDebugMessages == true then LOG(sFunctionRef..': About to see if factory '..oFactory.UnitId..M28UnitInfo.GetUnitLifetimeCount(oFactory)..'; can build blueprint '..sBlueprint..'; CanBuild='..tostring(oFactory:CanBuild(sBlueprint))) end
            if oFactory:CanBuild(sBlueprint) == true then
                --Check we can build the desired category
                if not(iOptionalCategoryThatMustBeAbleToBuild) then bCanBuildRequiredCategory = true
                else
                    if bDebugMessages == true then LOG(sFunctionRef..': Have said we need to build a particualr category, will see if sBLueprint='..sBlueprint..' can build this') end
                    bCanBuildRequiredCategory = false
                    iCategoriesThatBlueprintCanBuild = nil
                    if tAllBlueprints[sBlueprint].Economy.BuildableCategory and not(M28Utilities.IsTableEmpty(tsBlueprintsMeetingDesiredCategoriesToBuild)) then
                        if bDebugMessages == true then LOG(sFunctionRef..': sBlueprint has a buildablecategory set, will convert it into a category and see if it matches any of the blueprints we want to be able to build') end
                        for categoryIndex, category in tAllBlueprints[sBlueprint].Economy.BuildableCategory do
                            if categoryIndex == 1 then
                                iCategoriesThatBlueprintCanBuild = ParseEntityCategory(category)
                            else
                                iCategoriesThatBlueprintCanBuild = iCategoriesThatBlueprintCanBuild + ParseEntityCategory(category)
                            end
                        end

                        for iAltBlueprint, sAltBlueprint in tsBlueprintsMeetingDesiredCategoriesToBuild do
                            if bDebugMessages == true then LOG(sFunctionRef..': Considering if sAltBlueprint='..(sAltBlueprint or 'nil')..' has a category that matches with what sBLueprint can build') end
                            if EntityCategoryContains(iCategoriesThatBlueprintCanBuild, sAltBlueprint) then
                                if bDebugMessages == true then LOG(sFunctionRef..': Can build the desired category') end
                                bCanBuildRequiredCategory = true
                                break
                            end
                        end
                    end
                end

                if bCanBuildRequiredCategory then
                    --if EntityCategoryContains(iCategoryCondition, sBlueprint) then --tBlueprints is already filtered to just those that meet the categories
                    iValidBlueprints = iValidBlueprints + 1
                    tValidBlueprints[iValidBlueprints] = sBlueprint
                    if bIgnoreTechDifferences then iCurrentTech = 1
                    else
                        if EntityCategoryContains(categories.TECH3 + categories.EXPERIMENTAL, sBlueprint) then iCurrentTech = 3
                        elseif EntityCategoryContains(categories.TECH2, sBlueprint) then iCurrentTech = 2
                        else iCurrentTech = 1
                        end
                    end
                    if bDebugMessages == true then LOG(sFunctionRef..': '..sBlueprint..': iCurrentTech='..iCurrentTech..'; iHighestTech='..iHighestTech) end
                    if iCurrentTech > iHighestTech then
                        iHighestTech = iCurrentTech
                        iHighestPriority = 0
                    end
                    if bDebugMessages == true then LOG(sFunctionRef..': Considering if sBlueprint has a priority specified if we arent looking for slowest or fastest. sBlueprint='..sBlueprint..'; bGetSlowest='..tostring(bGetSlowest)..'; bGetFastest='..tostring(bGetFastest)..'; bGetCheapest='..tostring((bGetCheapest or false))) end
                    if not(bGetSlowest) and not(bGetFastest) and not(bGetCheapest) and aiBrain[reftBlueprintPriorityOverride][sBlueprint] then
                        if bDebugMessages == true then LOG(sFunctionRef..': Have a priority specified='..aiBrain[reftBlueprintPriorityOverride][sBlueprint]..'; iHighestPriority='..iHighestPriority) end
                        iHighestPriority = math.max(aiBrain[reftBlueprintPriorityOverride][sBlueprint], iHighestPriority)
                    end
                    if bGetSlowest == true or bGetFastest == true then
                        oCurBlueprint = tAllBlueprints[sBlueprint]
                        iCurSpeed = oCurBlueprint.Physics.MaxSpeed
                        if bDebugMessages == true then LOG(sFunctionRef..': '..sBlueprint..': iCurSpeed='..iCurSpeed) end
                        if bGetSlowest == true then
                            if iCurSpeed < tiLowestSpeedByTech[iCurrentTech] then tiLowestSpeedByTech[iCurrentTech] = iCurSpeed end
                        elseif bGetFastest == true then
                            if iCurSpeed > tiHighestSpeedByTech[iCurrentTech] then tiHighestSpeedByTech[iCurrentTech] = iCurSpeed end
                        end
                    elseif bGetCheapest then
                        oCurBlueprint = tAllBlueprints[sBlueprint]
                        iCurMass = oCurBlueprint.Economy.BuildCostMass
                        if iCurMass < tiLowestMassByTech[iCurrentTech] then tiLowestMassByTech[iCurrentTech] = iCurMass end
                        if bDebugMessages == true then LOG(sFunctionRef..': Want to get cheapest; iCurMass='..iCurMass..'; iCurrentTech='..iCurrentTech..'; tiLowestMassByTech[iCurrentTech]='..tiLowestMassByTech[iCurrentTech]) end
                    end
                    --end
                end
            end
        end
        --Now get a list of blueprints that are this tech level and of the highest priority
        --if bDebugMessages == true then LOG(sFunctionRef..': iHighestTech='..iHighestTech..'; tiHighestSpeedByTech='..tiHighestSpeedByTech[iHighestTech]..'; bGetSlowest='..tostring(bGetSlowest)..'; bGetFastest='..tostring(bGetFastest)) end
        local bIsValid, iCurrentPriority
        local iMinTechToUse = iHighestTech
        local iFastestSpeed = tiHighestSpeedByTech[iHighestTech]
        if bGetFastest == true and iHighestTech >= 3 then
            --If cybran, want loyalist instead of bomb; if Aeon want blaze instead of harbinger or shield disrupter; If sera probably want hover tank instead of siege tank; if UEF want titan
            if tiHighestSpeedByTech[3] <= 3.5 and tiHighestSpeedByTech[2] - tiHighestSpeedByTech[3] >= 0.6 then
                iMinTechToUse = 2
                iFastestSpeed = math.max(tiHighestSpeedByTech[3], tiHighestSpeedByTech[2])
            end
        end

        for _, sBlueprint in tValidBlueprints do
            bIsValid = false
            if EntityCategoryContains(categories.TECH3 + categories.EXPERIMENTAL, sBlueprint) then iCurrentTech = 3
            elseif EntityCategoryContains(categories.TECH2, sBlueprint) then iCurrentTech = 2
            else iCurrentTech = 1
            end
            if bDebugMessages == true then LOG(sFunctionRef..': sBlueprint='..sBlueprint..': Considering whether we have high enough tech to consider') end
            if iCurrentTech >= iMinTechToUse then
                if not(bGetFastest) and not(bGetSlowest) and not(bGetCheapest) then iCurrentPriority = aiBrain[reftBlueprintPriorityOverride][sBlueprint] end
                if iCurrentPriority == nil then iCurrentPriority = 0 end
                if bDebugMessages == true then LOG(sFunctionRef..': sBlueprint='..sBlueprint..'; iCurrentTech='..iCurrentTech..'; considering priority, iCurrentPriority='..iCurrentPriority..'; iHighestPriority='..iHighestPriority) end
                if iCurrentPriority >= iHighestPriority then
                    bIsValid = true

                    if not(bGetSlowest) and not(bGetFastest) and not(bGetCheapest) then
                        if bDebugMessages == true then LOG(sFunctionRef..': Not interested in if slowest or fastest or cheapest so marking BP as valid') end
                        bIsValid = true
                    else
                        if bDebugMessages == true then LOG(sFunctionRef..': Want to get either the slowest, fastest or cheapest') end
                        bIsValid = false
                        if bGetSlowest or bGetFastest then
                            oCurBlueprint = tAllBlueprints[sBlueprint]
                            iCurSpeed = oCurBlueprint.Physics.MaxSpeed
                            if bDebugMessages == true then LOG(sFunctionRef..': sBlueprint='..sBlueprint..'; iCurSpeed='..iCurSpeed) end
                            if bGetSlowest == true then
                                if iCurSpeed <= tiLowestSpeedByTech[iHighestTech] then bIsValid = true end
                            elseif iCurSpeed >= iFastestSpeed then
                                if bDebugMessages == true then LOG(sFunctionRef..': Have the highest speed for tech levels being considered') end
                                bIsValid = true
                            end
                        elseif bGetCheapest then
                            oCurBlueprint = tAllBlueprints[sBlueprint]
                            iCurMass = oCurBlueprint.Economy.BuildCostMass
                            if iCurMass <= tiLowestMassByTech[iCurrentTech] then bIsValid = true end
                            if bDebugMessages == true then LOG(sFunctionRef..': Want to get cheapest; iCurMass='..iCurMass..'; iCurrentTech='..iCurrentTech..'; tiLowestMassByTech[iCurrentTech]='..tiLowestMassByTech[iCurrentTech]..'; bIsValid='..tostring(bIsValid)) end
                        else M28Utilities.ErrorHandler('Missing code')
                        end
                    end
                end
                if bIsValid == true then
                    iBestBlueprints = iBestBlueprints + 1
                    tBestBlueprints[iBestBlueprints] = sBlueprint
                    if bDebugMessages == true then LOG(sFunctionRef..': Have valid blueprint='..sBlueprint) end
                end
            end
        end

        local iBPToBuild = math.random(1, iBestBlueprints)
        M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
        return tBestBlueprints[iBPToBuild]
    end


end

function AdjustBlueprintForOverrides(aiBrain, sBPIDToBuild, tLZTeamData, iFactoryTechLevel)
    --Blacklisted units
    if M28Team.tLandSubteamData[aiBrain.M28LandSubteam][M28Team.subrefBlueprintBlacklist][sBPIDToBuild] then
        sBPIDToBuild = nil
    else
        --Special case - Cybran and UEF - if building loyalists or titans, then check if want to switch to bricks/percies
        if sBPIDToBuild == 'url0303' then --Loyalist
            if M28Conditions.GetLifetimeBuildCount(aiBrain, M28UnitInfo.refCategoryLandCombat * categories.TECH3) >= 5 then
                aiBrain[reftBlueprintPriorityOverride]['url0303'] = nil --loyalist
                aiBrain[reftBlueprintPriorityOverride]['xrl0305'] = 1 --brick
            end
        elseif sBPIDToBuild == 'uel0303' then --Titan
            if M28Conditions.GetLifetimeBuildCount(aiBrain, M28UnitInfo.refCategoryLandCombat * categories.TECH3) >= 15 then
                aiBrain[reftBlueprintPriorityOverride]['url0303'] = nil --Titan
                aiBrain[reftBlueprintPriorityOverride]['xel0305'] = 1 --Percival
            end
        end

        if EntityCategoryContains(M28UnitInfo.refCategoryEngineer, sBPIDToBuild) then
            --Engineers - dont build if we have spare engineers at our current LZ
            local iMaxSpareWanted = 0
            if not(M28Conditions.TeamHasLowMass(aiBrain.M28Team)) then
                iMaxSpareWanted = math.max(1, math.floor(M28Team.tTeamData[aiBrain.M28Team][M28Team.subrefiTeamLowestMassPercentStored] * 10)) * M28Engineer.tiBPByTech[iFactoryTechLevel]
            end
            if tLZTeamData[M28Map.subrefLZSpareBPByTech][iFactoryTechLevel] > iMaxSpareWanted then
                sBPIDToBuild = nil
            end
        end
    end
    return sBPIDToBuild
end

function GetBlueprintToBuildForLandFactory(aiBrain, oFactory)
    local sFunctionRef = 'GetBlueprintToBuildForLandFactory'
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iCategoryToBuild
    local iPlateau, iLandZone = M28Map.GetPlateauAndLandZoneReferenceFromPosition(oFactory:GetPosition(), true, oFactory)
    local tLZTeamData = M28Map.tAllPlateaus[iPlateau][M28Map.subrefPlateauLandZones][iLandZone][M28Map.subrefLZTeamData][aiBrain.M28Team]
    local iFactoryTechLevel = M28UnitInfo.GetUnitTechLevel(oFactory)

    local iTeam = aiBrain.M28Team
    local bHaveLowMass = M28Conditions.TeamHasLowMass(iTeam)


    iCategoryToBuild = M28UnitInfo.refCategoryEngineer --Placeholder
    local sBPIDToBuild

    --subfunctions to mean we can do away with the 'current condition == 1, == 2.....==999 type approach making it much easier to add to
    function ConsiderBuildingCategory(iCategoryToBuild)
        sBPIDToBuild = GetBlueprintsThatCanBuildOfCategory(aiBrain, iCategoryToBuild, oFactory, nil, nil, nil, nil, false)
        if sBPIDToBuild then
            sBPIDToBuild = AdjustBlueprintForOverrides(aiBrain, sBPIDToBuild, tLZTeamData, iFactoryTechLevel)
        end
        if sBPIDToBuild then
            M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd) --Assumes we will end code if we get to this point
            return sBPIDToBuild
        end

    end

    local iCurrentConditionToTry = 0

    --MAIN BUILDER LOGIC:

    --Initial engineers
    iCurrentConditionToTry = iCurrentConditionToTry + 1
    if bDebugMessages == true then LOG(sFunctionRef..': Considering high priority engineers, iFactoryTechLevel='..iFactoryTechLevel..'; Team highest factory tech level='..M28Team.tTeamData[iTeam][M28Team.subrefiHighestFriendlyFactoryTech]..'; Lifetime build count='..M28Conditions.GetLifetimeBuildCount(aiBrain, M28UnitInfo.refCategoryEngineer * M28UnitInfo.ConvertTechLevelToCategory(iFactoryTechLevel))..'; Current units='..aiBrain:GetCurrentUnits(M28UnitInfo.refCategoryEngineer * M28UnitInfo.ConvertTechLevelToCategory(iFactoryTechLevel))) end
    if iFactoryTechLevel >= M28Team.tTeamData[iTeam][M28Team.subrefiHighestFriendlyFactoryTech] then
        if M28Conditions.GetLifetimeBuildCount(aiBrain, M28UnitInfo.refCategoryEngineer * M28UnitInfo.ConvertTechLevelToCategory(iFactoryTechLevel)) <= 4 or aiBrain:GetCurrentUnits(M28UnitInfo.refCategoryEngineer * M28UnitInfo.ConvertTechLevelToCategory(iFactoryTechLevel)) <= 2 then
            if ConsiderBuildingCategory(M28UnitInfo.refCategoryEngineer) then return sBPIDToBuild end
        end
    end

    --Scouts if we want any
    iCurrentConditionToTry = iCurrentConditionToTry + 1
    if tLZTeamData[M28Map.refbWantLandScout] then
        if ConsiderBuildingCategory(M28UnitInfo.refCategoryLandScout) then return sBPIDToBuild end
    end

    --Engineers if we have mass
    iCurrentConditionToTry = iCurrentConditionToTry + 1
    if M28Team.tTeamData[iTeam][M28Team.subrefiTeamLowestMassPercentStored] > 0.01 then
        if ConsiderBuildingCategory(M28UnitInfo.refCategoryEngineer) then return sBPIDToBuild end
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
    return sBPIDToBuild
end

function DetermineWhatToBuild(aiBrain, oFactory)
    local sBPIDToBuild

    if EntityCategoryContains(M28UnitInfo.refCategoryLandFactory, oFactory.UnitId) then
        sBPIDToBuild = GetBlueprintToBuildForLandFactory(aiBrain, oFactory)
    else
        M28Utilities.ErrorHandler('Need to add code')
    end

    return sBPIDToBuild
end

function IsFactoryReadyToBuild(oFactory)
    if oFactory:GetFractionComplete() == 1 and oFactory:GetWorkProgress() == 0 and oFactory:GetFractionComplete() == 1 and not(oFactory:IsUnitState('Building')) and not(oFactory:IsUnitState('Upgrading')) and not(oFactory:IsUnitState('Busy')) and M28Utilities.IsTableEmpty(oFactory:GetCommandQueue()) then
        return true
    end
    return false
end

function DecideAndBuildUnitForFactory(aiBrain, oFactory, bDontWait)
    --If factory is idle then gets it to build something; if its not idle then keeps checking for up to 20 seconds, but will abort if the factory appears to be building something
    local sFunctionRef = 'DecideAndBuildUnitForFactory'
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iTicksWaited = 0

    local bProceed = bDontWait
    if not(bProceed) then
        bProceed = IsFactoryReadyToBuild(oFactory)
    end

    local iWorkProgressStart = (oFactory:GetWorkProgress() or 0)

    while not(bProceed) do
        M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
        WaitTicks(1)
        M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)
        iTicksWaited = iTicksWaited + 1
        bProceed = IsFactoryReadyToBuild(oFactory)
        if M28UnitInfo.IsUnitValid(oFactory) == false then return nil end
        if oFactory:GetWorkProgress() > iWorkProgressStart then
            if bDebugMessages == true then LOG(sFunctionRef..': Factory work progress is going up so will abort as it presumably already has an order') end
            break
        end
        if iTicksWaited >= 200 then
            M28Utilities.ErrorHandler('oFactory has waited more than 200 ticks and still isnt showing as ready to build, oFactory='..oFactory.UnitId..M28UnitInfo.GetUnitLifetimeCount(oFactory)..'; brain nickname='..oFactory:GetAIBrain().Nickname..'; Work progress='..oFactory:GetWorkProgress()..'; Factory fraction complete='..oFactory:GetFractionComplete()..'; Factory status='..M28UnitInfo.GetUnitState(oFactory)..'; Is command queue empty='..tostring(M28Utilities.IsTableEmpty(oFactory:GetCommandQueue()))..'; iWorkProgressStart='..(iWorkProgressStart or 'nil'))
            break
        end
    end
    if bProceed then

        local sBPToBuild = DetermineWhatToBuild(aiBrain, oFactory)
        if bDebugMessages == true then LOG(sFunctionRef..': oFactory='..oFactory.UnitId..M28UnitInfo.GetUnitLifetimeCount(oFactory)..'; sBPToBuild='..(sBPToBuild or 'nil')..'; Does factory have an empty command queue='..tostring(M28Utilities.IsTableEmpty(oFactory:GetCommandQueue()))..'; Factory work progress='..oFactory:GetWorkProgress()..'; Factory unit state='..M28UnitInfo.GetUnitState(oFactory)) end
        if sBPToBuild then
            M28Orders.IssueTrackedFactoryBuild(oFactory, sBPToBuild, bDontWait)
        end
    end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

function SetPreferredUnitsByCategory(aiBrain)
    --If have multiple units that can build for a particular category, this will specify what to build
    --special cases where want to prioritise one unit over another where multiple of same type satisfy the category
    --NOTE: This gets ignored if we have coded in special cases where we want to pick the fastest or slowest unit
    aiBrain[reftBlueprintPriorityOverride] = {}
    --T1
    aiBrain[reftBlueprintPriorityOverride]['ual0201'] = 1 --Aurora (instead of LAB)
    aiBrain[reftBlueprintPriorityOverride]['url0107'] = 1 --Mantis (instead of LAB)
    aiBrain[reftBlueprintPriorityOverride]['uel0201'] = 1 --Striker (instead of mechmarine)
    aiBrain[reftBlueprintPriorityOverride]['xsl0201'] = 1 --Thaam (instead of combat scout)
    --T2
    aiBrain[reftBlueprintPriorityOverride]['uel0202'] = 1 --Pillar (instead of mongoose or riptide)
    aiBrain[reftBlueprintPriorityOverride]['xsl0202'] = 1 --Ilshavoh (instead of hover tank)
    aiBrain[reftBlueprintPriorityOverride]['url0202'] = 1 --Rhino (instead of hover tank)
    aiBrain[reftBlueprintPriorityOverride]['ual0202'] = 1 --Obsidian (instead of blaze)
    --T3
    aiBrain[reftBlueprintPriorityOverride]['uel0303'] = 1 --Titan (instead of Percy)
    aiBrain[reftBlueprintPriorityOverride]['ual0303'] = 1 --Harby (instead of sniper bot)
    --aiBrain[reftBlueprintPriorityOverride]['ual0304'] = 1 --Mobile t3 arti instead of shield disrupter
    aiBrain[reftBlueprintPriorityOverride]['url0303'] = 1 --Loyalist (instead of Brick)
    --aiBrain[reftBlueprintPriorityOverride]['xrl0305'] = 1 --Brick
    aiBrain[reftBlueprintPriorityOverride]['xsl0303'] = 1 --Siege tank (instead of sniper bot)
    aiBrain[reftBlueprintPriorityOverride]['xsl0301'] = 1 --Seraphim basic SACU (instead of preset)

    --Engineers
    aiBrain[reftBlueprintPriorityOverride]['uel0208'] = 1 --T2 Engi (instead of sparky)

end


function IdleFactoryMonitor(aiBrain)
    --Cycles through every factory owned by aiBrain, max of 1 factory per tick, to check if it is idle
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'IdleFactoryMonitor'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    while not(aiBrain.M28IsDefeated) do
        local tOurFactories = aiBrain:GetListOfUnits(M28UnitInfo.refCategoryFactory, false, true)
        local tCommandQueue
        local sBPToBuild
        if M28Utilities.IsTableEmpty(tOurFactories) == false then
            for iFactory, oFactory in tOurFactories do
                if M28UnitInfo.IsUnitValid(oFactory) and oFactory:GetFractionComplete() == 1 then
                    tCommandQueue = oFactory:GetCommandQueue()
                    if IsFactoryReadyToBuild(oFactory) and GetGameTimeSeconds() - (oFactory[refiTimeSinceLastOrderCheck] or 0) >= 5 then
                        oFactory[refiTimeSinceLastOrderCheck] = GetGameTimeSeconds()
                        ForkThread(DecideAndBuildUnitForFactory, aiBrain, oFactory)
                    end
                end
                M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
                WaitTicks(1)
                M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)
            end
        end
        M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
        WaitTicks(1)
        M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)
    end
end