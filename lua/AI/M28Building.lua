---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 29/01/2023 18:46
---

local M28Team = import('/mods/M28AI/lua/AI/M28Team.lua')
local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')
local M28Map = import('/mods/M28AI/lua/AI/M28Map.lua')
local M28Profiler = import('/mods/M28AI/lua/AI/M28Profiler.lua')
local M28UnitInfo = import('/mods/M28AI/lua/AI/M28UnitInfo.lua')

--Global variables
iTMLMissileRange = 256 --e.g. use if dont have access to a unit blueprint


--Variables against a unit
reftTMLInRangeOfThisUnit = 'M28BuildTMLInRange' --Records table of TML in range of this unit
reftUnitsInRangeOfThisTML = 'M28BuildUnitsInRangeOfTML' --Records units threatened by this TML
reftUnitsCoveredByThisTMD = 'M28BuildUnitsCoveredByTMD' --Against TMD, table of units that it provides TML coverage to
reftTMDCoveringThisUnit = 'M28BuildTMDCoveringUnit' --against unit, table of TMD providing TML coverage to it
refbUnitWantsMoreTMD = 'M28BuildUnitWantsTMD' --true if a unit wants more TMD
refbNoNearbyTMDBuildLocations = 'M28BuiltUnitHasNoNearbyTMDBuildLocations' --true if we buitl a TMD to cover this unit and the TMD ended up too far away

function EnemyTMLFirstRecorded(iTeam, oTML)
    --Have just recorded an enemy TML against a land zone - want to record the TML against all units in its range who will want protecting from it
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'EnemyTMLFirstRecorded'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local aiBrain = M28Team.tTeamData[iTeam][M28Team.subreftoFriendlyActiveM28Brains][1]
    if bDebugMessages == true then LOG(sFunctionRef..': Enemy TML '..oTML.UnitId..M28UnitInfo.GetUnitLifetimeCount(oTML)..' just recorded for iTeam '..iTeam..'; Team active M28 brain count='..M28Team.tTeamData[iTeam][M28Team.subrefiActiveM28BrainCount]) end
    if aiBrain then
        local iTMLRange = (oTML[M28UnitInfo.refiManualRange] or iTMLMissileRange + 4) --slight buffer given aoe and building sizes
        --Record for this team in the global list
        table.insert(M28Team.tTeamData[iTeam][M28Team.reftEnemyTML], oTML)
        --Record against each unit that it is in range of
        local tUnitsToProtect = aiBrain:GetUnitsAroundPoint(M28UnitInfo.refCategoryProtectFromTML, oTML:GetPosition(), iTMLRange, 'Ally')
        if bDebugMessages == true then LOG(sFunctionRef..': iTMlRange='..iTMLRange..'; Is table of units to protect empty for brian '..aiBrain.Nickname..'='..tostring(M28Utilities.IsTableEmpty(tUnitsToProtect))) end
        if M28Utilities.IsTableEmpty(tUnitsToProtect) == false then
            oTML[reftUnitsInRangeOfThisTML] = {}
            for iUnit, oUnit in tUnitsToProtect do
                if not(M28UnitInfo.IsUnitUnderwater(oUnit)) then
                    table.insert(oTML[reftUnitsInRangeOfThisTML], oUnit)
                    --Record TML as being in range of the unit
                    if not(oUnit[reftTMLInRangeOfThisUnit]) then
                        oUnit[reftTMLInRangeOfThisUnit] = {}
                    end
                    table.insert(oUnit[reftTMLInRangeOfThisUnit], oTML)
                    if bDebugMessages == true then LOG(sFunctionRef..': Unit '..oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit)..' is in range of the TML so recording for boht the unit and TML') end
                end
            end
        end
        --Check if any of these units already have TMD protecting them (that may not have been recorded as protecting from this TML)
        if M28Utilities.IsTableEmpty(oTML[reftUnitsInRangeOfThisTML]) == false then
            local tProtectingTMD = aiBrain:GetUnitsAroundPoint(M28UnitInfo.refCategoryTMD, oTML:GetPosition(), iTMLRange + 16, 'Ally')
            if bDebugMessages == true then LOG(sFunctionRef..': Number of units in range of TML='..table.getn(oTML[reftUnitsInRangeOfThisTML])) end
            if M28Utilities.IsTableEmpty(tProtectingTMD) == false then
                UpdateTMDCoverageOfUnits(iTeam, tProtectingTMD, oTML[reftUnitsInRangeOfThisTML])
            else
                RecordIfUnitsWantTMDCoverageAgainstLandZone(iTeam, oTML[reftUnitsInRangeOfThisTML])
            end
        end
    end
end

function AlliedTMDFirstRecorded(iTeam, oTMD)
    --Have just recorded an allied TMD for a land zone - want to record all units within a long range that want protecting from TML if this provides protection from an enemy TML
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'AlliedTMDFirstRecorded'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    if bDebugMessages == true then LOG(sFunctionRef..': oTMD '..oTMD.UnitId..M28UnitInfo.GetUnitLifetimeCount(oTMD)..' has been identified, will reecord if are any enemy TML, is table of enemy TML empty='..tostring(M28Utilities.IsTableEmpty(M28Team.tTeamData[iTeam][M28Team.reftEnemyTML]))) end

    if M28Utilities.IsTableEmpty(M28Team.tTeamData[iTeam][M28Team.reftEnemyTML]) == false then
        local aiBrain = M28Team.tTeamData[iTeam][M28Team.subreftoFriendlyActiveM28Brains][1]
        local tUnitsToProtect = aiBrain:GetUnitsAroundPoint(M28UnitInfo.refCategoryProtectFromTML, oTMD:GetPosition(), iTMLMissileRange + 20, 'Ally')
        if M28Utilities.IsTableEmpty(tUnitsToProtect) == false then
            local tOnLandUnits = {}
            for iUnit, oUnit in tUnitsToProtect do
                if not(M28UnitInfo.IsUnitUnderwater(oUnit)) then
                    table.insert(tOnLandUnits, oUnit)
                end
            end
            if M28Utilities.IsTableEmpty(tOnLandUnits) == false then
                UpdateTMDCoverageOfUnits(iTeam,{ oTMD }, tOnLandUnits)
            end
        end
    end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

function TMLDied(oTML)
    --Updates tracking of the TML including for any units that had it recorded as being in range of them, and then checks if those units want TMD coverage (as there may no longer be any TML to protect from)

    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'TMLDied'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    if bDebugMessages == true then LOG(sFunctionRef..': TML has just died, is the table of units in range of it empty='..tostring(M28Utilities.IsTableEmpty(oTML[reftUnitsInRangeOfThisTML]))) end

    --Update each team that was tracking this
    for iTeam = 1, M28Team.iTotalTeamCount do
        if M28Utilities.IsTableEmpty(M28Team.tTeamData[iTeam][M28Team.reftEnemyTML]) == false and not(oTML:GetAIBrain().M28Team == iTeam) then
            for iRecordedTML, oRecordedTML in M28Team.tTeamData[iTeam][M28Team.reftEnemyTML] do
                if oRecordedTML == oTML then
                    table.remove(M28Team.tTeamData[iTeam][M28Team.reftEnemyTML], iRecordedTML)
                end
            end
        end
    end
    --Update each unit that was tracking this:
    if M28Utilities.IsTableEmpty(oTML[reftUnitsInRangeOfThisTML]) == false then
        local tUnitsToUpdateByTeam = {}
        local iCurTeam
        for iUnit, oUnit in oTML[reftUnitsInRangeOfThisTML] do
            if M28UnitInfo.IsUnitValid(oUnit) then
                for iExistingTML, oExistingTML in oUnit[reftTMLInRangeOfThisUnit] do
                    if oExistingTML == oTML then
                        iCurTeam = oUnit:GetAIBrain().M28Team
                        if not(tUnitsToUpdateByTeam[iCurTeam]) then tUnitsToUpdateByTeam[iCurTeam] = {} end
                        table.insert(tUnitsToUpdateByTeam[iCurTeam], oUnit)
                        table.remove(oUnit[reftTMLInRangeOfThisUnit], iExistingTML)
                        break
                    end
                end
            end
        end
        if M28Utilities.IsTableEmpty(tUnitsToUpdateByTeam) == false then
            for iTeam, tUnitList in tUnitsToUpdateByTeam do
                RecordIfUnitsWantTMDCoverageAgainstLandZone(iTeam, tUnitList)
            end
        end
    end
end
function TMDDied(oTMD)
    --Updates any units that were relying on oTMD for protection from TML, and reassesses if those units want more TMD now
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'TMDDied'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    if bDebugMessages == true then LOG(sFunctionRef..': TMD has just died, is the table of units covered by this TMD empty='..tostring(M28Utilities.IsTableEmpty(oTMD[reftUnitsCoveredByThisTMD]))) end
    if M28Utilities.IsTableEmpty(oTMD[reftUnitsCoveredByThisTMD]) == false then
        local tUnitsToCheckIfWantTMDCoverageByTeam = {}
        local iCurTeam
        for iUnit, oUnit in oTMD[reftUnitsCoveredByThisTMD] do
            if M28UnitInfo.IsUnitValid(oUnit) then
                for iRecordedTMD, oRecordedTMD in oUnit[reftTMDCoveringThisUnit] do
                    if oRecordedTMD == oTMD then
                        iCurTeam = oUnit:GetAIBrain().M28Team
                        if not(tUnitsToCheckIfWantTMDCoverage[iCurTeam]) then tUnitsToCheckIfWantTMDCoverage[iCurTeam] = {} end
                        table.insert(tUnitsToCheckIfWantTMDCoverage[iCurTeam], oUnit)
                        table.remove(oUnit[reftTMDCoveringThisUnit], iRecordedTMD)
                    end
                end
            end
        end
        if M28Utilities.IsTableEmpty(tUnitsToCheckIfWantTMDCoverageByTeam) == false then
            for iTeam, tUnitList in tUnitsToCheckIfWantTMDCoverageByTeam do
                RecordIfUnitsWantTMDCoverageAgainstLandZone(iTeam, tUnitList)
            end
        end
    end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

function UpdateTMDCoverageOfUnits(iTeam, tTMD, tUnitsToUpdate)
    --Goes through each unit in tUnitsToUpdate, and records any TMD in tTMD that can protect it from all TML in range of the unit
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'UpdateTMDCoverageOfUnits'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local tAllEnemyTML = M28Team.tTeamData[iTeam][M28Team.reftEnemyTML]
    if M28Utilities.IsTableEmpty(tAllEnemyTML) == false then --redundancy
        local bTMDCoversFromAllTML
        local bCanBlockCurTML
        local bAlreadyRecordedTMD = false
        local bAlreadyRecordedAsWantingTMD
        local iUnitToTMD, iUnitToTML, iTMDToTML, iTMDRange, iBuildingSize, iAngleTMLToTMD, iAngleTMLToUnit
        local iUnitPlateau, iUnitLandZone
        for iUnit, oUnit in tUnitsToUpdate do
            if M28Utilities.IsTableEmpty(oUnit[reftTMLInRangeOfThisUnit]) == false then
                iBuildingSize = M28UnitInfo.GetBuildingSize(oUnit.UnitId)
                for iTMD, oTMD in tTMD do
                    bTMDCoversFromAllTML = true
                    iUnitToTMD = M28Utilities.GetDistanceBetweenPositions(oTMD:GetPosition(), oUnit:GetPosition())
                    iTMDRange = (oUnit[M28UnitInfo.refiMissileDefenceRange] or 12.5)

                    --Reduce TMDRange to the effective range
                    iTMDRange = iTMDRange - iBuildingSize

                    for iTML, oTML in oUnit[reftTMLInRangeOfThisUnit] do
                        bCanBlockCurTML = false
                        iUnitToTML = M28Utilities.GetDistanceBetweenPositions(oTML:GetPosition(), oUnit:GetPosition())
                        iTMDToTML = M28Utilities.GetDistanceBetweenPositions(oTMD:GetPosition(), oTML:GetPosition())

                        iAngleTMLToUnit = M28Utilities.GetAngleFromAToB(oTML:GetPosition(), oUnit:GetPosition())
                        iAngleTMLToTMD = M28Utilities.GetAngleFromAToB(oTML:GetPosition(), oTMD:GetPosition())
                        if M28Utilities.IsLineFromAToBInRangeOfCircleAtC(iUnitToTML, iTMDToTML, iUnitToTMD, iAngleTMLToUnit, iAngleTMLToTMD, iTMDRange) then
                            --TMD can block the TML
                            if bDebugMessages == true then LOG(sFunctionRef..': oTMD='..oTMD.UnitId..M28UnitInfo.GetUnitLifetimeCount(oTMD)..' can block the TML so will record it') end
                            bCanBlockCurTML = true
                        end
                        if not(bCanBlockCurTML) then
                            bTMDCoversFromAllTML = false
                            break
                        end
                    end
                    if bTMDCoversFromAllTML then
                        if not(oUnit[reftTMDCoveringThisUnit]) then oUnit[reftTMDCoveringThisUnit] = {}
                        else
                            for iRecordedTMD, oRecordedTMD in oUnit[reftTMDCoveringThisUnit] do
                                if oRecordedTMD == oTMD then bAlreadyRecordedTMD = true  break end
                            end
                        end
                        if not(bAlreadyRecordedTMD) then
                            table.insert(oUnit[reftTMDCoveringThisUnit], oTMD)
                        end
                    end
                end
            end
        end
        RecordIfUnitsWantTMDCoverageAgainstLandZone(iTeam, tUnitsToUpdate)
    end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

function RecordIfUnitsWantTMDCoverageAgainstLandZone(iTeam, tUnits)
    --Cycles through each unit in tUnits and if it has less TMD covering it than TML in range, makes sure it is reecorded in its land zone as one of the units wanting TMD
    --If it has sufficient TMD coverage, then instead makes sure it isnt recorded in its land zone as one of the units wanting TMD
    --Relies on otherfunctions for accurately recording TML in range of it and TMD giving coverage

    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'RecordIfUnitsWantTMDCoverageAgainstLandZone'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iTMDInRange, iUnitPlateau, iUnitLandZone
    if bDebugMessages == true then LOG(sFunctionRef..': Start of code at time '..GetGameTimeSeconds()..'; size of tUnits='..table.getn(tUnits)..'; iTeam='..iTeam) end
    for iUnit, oUnit in tUnits do
        --Does the unit need TMD coverage?
        iTMDInRange = 0
        if M28Utilities.IsTableEmpty(oUnit[reftTMDCoveringThisUnit]) == false then iTMDInRange = table.getn(oUnit[reftTMDCoveringThisUnit]) end
        if bDebugMessages == true then LOG(sFunctionRef..': Considierng unit '..oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit)..'; iTMDInRange='..iTMDInRange..'; TML in range='..table.getn((oUnit[reftTMLInRangeOfThisUnit] or {}))..'; oUnit[refbUnitWantsMoreTMD]='..tostring(oUnit[refbUnitWantsMoreTMD] or false)) end
        if M28Utilities.IsTableEmpty(oUnit[reftTMLInRangeOfThisUnit]) == false and iTMDInRange < table.getn(oUnit[reftTMLInRangeOfThisUnit]) and not(oUnit[refbNoNearbyTMDBuildLocations]) then
            if not(oUnit[refbUnitWantsMoreTMD]) then --redundancy
                iUnitPlateau, iUnitLandZone = M28Map.GetPlateauAndLandZoneReferenceFromPosition(oUnit:GetPosition())
                if bDebugMessages == true then LOG(sFunctionRef..': Want TMD for this unit, iUnitPlateau='..(iUnitPlateau or 'nil')..'; iUnitLandZone='..(iUnitLandZone or 'nil')) end
                if iUnitLandZone > 0 then
                    local tLZTeamData = M28Map.tAllPlateaus[iUnitPlateau][M28Map.subrefPlateauLandZones][iUnitLandZone][M28Map.subrefLZTeamData][iTeam]
                    table.insert(tLZTeamData[M28Map.reftUnitsWantingTMD], oUnit)
                end
                oUnit[refbUnitWantsMoreTMD] = true
            end
        else
            if oUnit[refbUnitWantsMoreTMD] then
                --Remove this unit from the land zone list of units wanting TMD
                iUnitPlateau, iUnitLandZone = M28Map.GetPlateauAndLandZoneReferenceFromPosition(oUnit:GetPosition())
                if iUnitLandZone > 0 then
                    local tLZTeamData = M28Map.tAllPlateaus[iUnitPlateau][M28Map.subrefPlateauLandZones][iUnitLandZone][M28Map.subrefLZTeamData][iTeam]
                    if bDebugMessages == true then LOG(sFunctionRef..': Dont want TMD for this unit, iUnitPlateau='..(iUnitPlateau or 'nil')..'; iUnitLandZone='..(iUnitLandZone or 'nil')..'; is table of LZ units wanting TMD empty='..tostring(M28Utilities.IsTableEmpty(tLZTeamData[M28Map.reftUnitsWantingTMD]))) end
                    if M28Utilities.IsTableEmpty(tLZTeamData[M28Map.reftUnitsWantingTMD]) == false then
                        --Remove htis unit from the list of units wanting TMD
                        for iRecordedUnit, oRecordedUnit in tLZTeamData[M28Map.reftUnitsWantingTMD] do
                            if oRecordedUnit == oUnit then
                                table.remove(tLZTeamData[M28Map.reftUnitsWantingTMD], iRecordedUnit)
                                break
                            end
                        end
                    end
                end
                oUnit[refbUnitWantsMoreTMD] = false
            end
        end
    end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

function UpdateLZUnitsWantingTMDForUnitDeath(oUnit)
    --Updates any units currently recorded as wanting TMD to see if htey still want TMD based on TMD coverage
    local iUnitPlateau, iUnitLandZone = M28Map.GetPlateauAndLandZoneReferenceFromPosition(oUnit:GetPosition())
    if iUnitLandZone > 0 then
        local iTeam = oUnit:GetAIBrain().M28AITeam
        local tLZTeamData = M28Map.tAllPlateaus[iUnitPlateau][M28Map.subrefPlateauLandZones][iUnitLandZone][M28Map.subrefLZTeamData][iTeam]
        --Remove all dead units from the table (not just this one) as extra redundancy
        if M28Utilities.IsTableEmpty(tLZTeamData[M28Map.reftUnitsWantingTMD]) == false then
            local iRevisedIndex = 1
            local iTableSize = table.getn(tLZTeamData[M28Map.reftUnitsWantingTMD])

            for iOrigIndex=1, iTableSize do
                if tLZTeamData[M28Map.reftUnitsWantingTMD][iOrigIndex] then
                    if M28UnitInfo.IsUnitValid(tLZTeamData[M28Map.reftUnitsWantingTMD][iOrigIndex]) then --I.e. this should run the logic to decide whether we want to keep this entry of the table or remove it
                        --We want to keep the entry; Move the original index to be the revised index number (so if e.g. a table of 1,2,3 removed 2, then this would've resulted in the revised index being 2 (i.e. it starts at 1, then icnreases by 1 for the first valid entry); this then means we change the table index for orig index 3 to be 2
                        if (iOrigIndex ~= iRevisedIndex) then
                            tLZTeamData[M28Map.reftUnitsWantingTMD][iRevisedIndex] = tLZTeamData[M28Map.reftUnitsWantingTMD][iOrigIndex]
                            tLZTeamData[M28Map.reftUnitsWantingTMD][iOrigIndex] = nil
                        end
                        iRevisedIndex = iRevisedIndex + 1 --i.e. this will be the position of where the next value that we keep will be located
                    else
                        tLZTeamData[M28Map.reftUnitsWantingTMD][iOrigIndex] = nil
                    end
                end
            end
        end
    end
    oUnit[refbUnitWantsMoreTMD] = false --redundancy
end