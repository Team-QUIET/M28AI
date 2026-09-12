---
--- M28Intel.lua - Intel Confidence System
--- Created for M28AI to improve reconnaissance and tactical awareness
--- Provides intel confidence scoring for zones to enable smarter army movement
--- A lot of functions within this core intelligence file are not utilized yet
---

local M28Profiler = import('/mods/M28AI/lua/AI/M28Profiler.lua')
local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')
local M28Map = import('/mods/M28AI/lua/AI/M28Map.lua')
local M28Team = import('/mods/M28AI/lua/AI/M28Team.lua')
local M28UnitInfo = import('/mods/M28AI/lua/AI/M28UnitInfo.lua')

refiPlannedRadarCoverage = 'M28PlannedRadarCoverage'
refiPlannedSonarCoverage = 'M28PlannedSonarCoverage'
refoPlannedRadar = 'M28PlannedRadar'
refoPlannedSonar = 'M28PlannedSonar'
local tIntelSources = {}
local tIntelSourceStates = {}
local tCoverageOmniTeams = {}
local bCoverageMonitorRunning = false
local bCoverageDirty = false

function GetOperationalIntelRadius(oUnit, sIntel)
    if not(M28UnitInfo.IsUnitValid(oUnit)) or oUnit:GetFractionComplete() < 1 or oUnit:IsUnitState('Attached')
            or not(oUnit:IsIntelEnabled(sIntel)) then return 0 end
    return math.max(0, oUnit:GetIntelRadius(sIntel) or 0)
end

function GetPlannedRadarCoverage(tZoneTeamData)
    return math.max(tZoneTeamData[M28Map.refiRadarCoverage] or 0, tZoneTeamData[refiPlannedRadarCoverage] or 0)
end

function RecordZoneVisualFromUnit(oUnit, tZone, tZoneTeamData)
    if not(M28UnitInfo.IsUnitValid(oUnit)) or oUnit:GetFractionComplete()<1 or oUnit:IsUnitState('Attached') then return false end
    local sLayer = oUnit:GetCurrentLayer()
    local sVision = (sLayer=='Sub' or sLayer=='Seabed') and 'WaterVision' or 'Vision'
    local iRadius = GetOperationalIntelRadius(oUnit,sVision)
    if iRadius>0 and M28Utilities.GetDistanceBetweenPositions(oUnit:GetPosition(),tZone[M28Map.subrefMidpoint]) <= iRadius then
        tZoneTeamData[M28Map.refiTimeLastHadVisual] = GetGameTimeSeconds()
        tZoneTeamData[refiTimeLastIntelUpdate] = nil
        return true
    end
    return false
end

function GetKnownThreatPosition(aiBrain, oUnit, iMaxAge)
    if not(aiBrain) or not(M28UnitInfo.IsUnitValid(oUnit)) then return nil, 0, 0 end
    if M28UnitInfo.CanSeeUnit(aiBrain, oUnit) then
        M28Team.UpdateUnitLastKnownPosition(aiBrain, oUnit, true)
        return oUnit:GetPosition(), 1, 0
    end
    local tPositions = oUnit[M28UnitInfo.reftLastKnownPositionByTeam]
    local tTimes = oUnit[M28UnitInfo.reftLastContactTimeByTeam]
    local iTeam = aiBrain.M28Team
    local tPosition = tPositions and tPositions[iTeam]
    local iSeen = tTimes and tTimes[iTeam]
    if not(tPosition) or not(iSeen) then return nil, 0, 0 end
    local iAge = math.max(0, GetGameTimeSeconds() - iSeen)
    if EntityCategoryContains(categories.STRUCTURE, oUnit.UnitId) then return tPosition, 1, iAge end
    iMaxAge = iMaxAge or 60
    if iAge >= iMaxAge then return nil, 0, iAge end
    -- Keep a recent army dangerous while its possible position becomes less precise.
    local iConfidence = math.max(0, math.min(1, (iMaxAge-iAge) / (iMaxAge*0.6)))
    return tPosition, iConfidence, iAge
end

function GetKnownGroundAA(aiBrain)
    local tKnown = M28Team.tTeamData[aiBrain.M28Team][M28Team.reftoKnownGroundAA] or {}
    local tResult = {}
    for iId, oUnit in tKnown do
        if not(M28UnitInfo.IsUnitValid(oUnit)) or not(IsEnemy(aiBrain:GetArmyIndex(), oUnit:GetArmy())) then
            tKnown[iId] = nil
        else
            table.insert(tResult, oUnit)
        end
    end
    table.sort(tResult, function(a,b) return a.EntityId < b.EntityId end)
    return tResult
end

function WantsForwardRadar(tZoneTeamData)
    return not(tZoneTeamData[M28Map.subrefLZbCoreBase])
        and not(tZoneTeamData[M28Map.subrefbDangerousEnemiesInThisLZ])
        and (tZoneTeamData[M28Map.refiRadarCoverage] or 0) < 60
        and (tZoneTeamData[M28Map.refiOmniCoverage] or 0) < 60
        and (tZoneTeamData[M28Map.subrefLZThreatAllyMobileDFTotal] or 0) >= 300
end

local function IntelSourceStateChanged(tOld, tNew)
    if not(tOld) then return true end
    for _, sKey in {'team', 'army', 'x', 'z', 'radar', 'omni', 'sonar', 'plannedRadar', 'plannedSonar'} do
        if tOld[sKey] ~= tNew[sKey] then return true end
    end
    return false
end

function RefreshOperationalIntelCoverage(bForce)
    if not(M28Map.bMapLandSetupComplete) or not(M28Map.bWaterZoneInitialCreation) then return end
    local bChanged = bForce or bCoverageDirty
    local tSources, tTeams = {}, {}
    for oUnit, _ in tIntelSources do
        if M28UnitInfo.IsUnitValid(oUnit) then
            table.insert(tSources, oUnit)
        else
            tIntelSources[oUnit] = nil
            tIntelSourceStates[oUnit] = nil
            bChanged = true
        end
    end
    table.sort(tSources, function(a,b) return a.EntityId < b.EntityId end)
    for _, oUnit in tSources do
        local oBrain = oUnit:GetAIBrain()
        local tPosition = oUnit:GetPosition()
        local tIntel = oUnit:GetBlueprint().Intel or {}
        local bUnfinished = oUnit:GetFractionComplete() < 1
        local tState = {team=oBrain.M28Team, army=oBrain:GetArmyIndex(), x=tPosition[1], z=tPosition[3],
            radar=GetOperationalIntelRadius(oUnit, 'Radar'), omni=GetOperationalIntelRadius(oUnit, 'Omni'),
            sonar=GetOperationalIntelRadius(oUnit, 'Sonar'),
            plannedRadar=bUnfinished and (tIntel.RadarRadius or 0) or 0,
            plannedSonar=bUnfinished and (tIntel.SonarRadius or 0) or 0}
        if IntelSourceStateChanged(tIntelSourceStates[oUnit], tState) then bChanged = true end
        tIntelSourceStates[oUnit] = tState
    end
    for iTeam, tTeam in M28Team.tTeamData do
        if (tTeam[M28Team.subrefiActiveM28BrainCount] or 0) > 0 then
            table.insert(tTeams, iTeam)
            local bOmni = tTeam[M28Team.subrefbTeamHasOmniVision] or false
            if tCoverageOmniTeams[iTeam] ~= bOmni then bChanged = true end
            tCoverageOmniTeams[iTeam] = bOmni
        end
    end
    if not(bChanged) then return end
    table.sort(tTeams)
    bCoverageDirty = false
    local function RefreshZone(tZone, sTeamData, bWater)
        local tMidpoint = tZone[M28Map.subrefMidpoint]
        local tAllOmni, iAllOmni = {}, 0
        for _, oUnit in tSources do
            local tState = tIntelSourceStates[oUnit]
            local iDistance = math.sqrt((tState.x-tMidpoint[1]) * (tState.x-tMidpoint[1]) + (tState.z-tMidpoint[3]) * (tState.z-tMidpoint[3]))
            if tState.omni > iDistance then
                table.insert(tAllOmni, oUnit)
                iAllOmni = math.max(iAllOmni, tState.omni-iDistance)
            end
        end
        tZone[M28Map.reftoAllOmniRadar] = tAllOmni
        tZone[M28Map.refiAllOmniCoverage] = iAllOmni
        for _, iTeam in tTeams do
            local tData = tZone[sTeamData] and tZone[sTeamData][iTeam]
            if tData then
                local tValues = {radar=0, omni=0, sonar=0, plannedRadar=0, plannedSonar=0}
                local tBest = {}
                for _, oUnit in tSources do
                    local tState = tIntelSourceStates[oUnit]
                    if tState.team == iTeam then
                        local iDistance = math.sqrt((tState.x-tMidpoint[1]) * (tState.x-tMidpoint[1]) + (tState.z-tMidpoint[3]) * (tState.z-tMidpoint[3]))
                        for _, sKind in {'radar', 'omni', 'sonar', 'plannedRadar', 'plannedSonar'} do
                            local iCoverage = tState[sKind] - iDistance
                            if iCoverage > tValues[sKind] then tValues[sKind] = iCoverage; tBest[sKind] = oUnit end
                        end
                    end
                end
                local bOmni = tCoverageOmniTeams[iTeam]
                tData[M28Map.refiRadarCoverage] = bOmni and 5000 or tValues.radar
                tData[M28Map.refiOmniCoverage] = bOmni and 5000 or tValues.omni
                tData[M28Map.refoBestRadar] = tBest.radar
                tData[refiPlannedRadarCoverage] = tValues.plannedRadar
                tData[refoPlannedRadar] = tBest.plannedRadar
                if bWater then
                    tData[M28Map.refiSonarCoverage] = bOmni and 5000 or tValues.sonar
                    tData[M28Map.refoBestSonar] = tBest.sonar
                    tData[refiPlannedSonarCoverage] = tValues.plannedSonar
                    tData[refoPlannedSonar] = tBest.plannedSonar
                end
                tData[refiTimeLastIntelUpdate] = nil
            end
        end
    end
    for _, tPlateau in M28Map.tAllPlateaus do
        for _, tZone in tPlateau[M28Map.subrefPlateauLandZones] or {} do RefreshZone(tZone, M28Map.subrefLZTeamData, false) end
    end
    for _, tPond in M28Map.tPondDetails do
        for _, tZone in tPond[M28Map.subrefPondWaterZones] or {} do RefreshZone(tZone, M28Map.subrefWZTeamData, true) end
    end
end

local function MonitorOperationalIntelCoverage()
    while true do
        RefreshOperationalIntelCoverage(false)
        if M28Utilities.IsTableEmpty(tIntelSources) then break end
        WaitTicks(21)
    end
    bCoverageMonitorRunning = false
end

function RegisterIntelSource(oUnit)
    if M28UnitInfo.IsUnitValid(oUnit) then tIntelSources[oUnit] = true end
    bCoverageDirty = true
    if not(bCoverageMonitorRunning) then
        bCoverageMonitorRunning = true
        ForkThread(MonitorOperationalIntelCoverage)
    end
end

function InvalidateIntelSource(oUnit)
    tIntelSources[oUnit] = nil
    tIntelSourceStates[oUnit] = nil
    bCoverageDirty = true
    RefreshOperationalIntelCoverage(true)
end

--===========================================
-- INTEL CONFIDENCE CONFIGURATION
--===========================================

-- Time thresholds (in seconds) for visual confidence decay
iVisualFullConfidenceTime = 30      -- Full confidence if scouted within this time
iVisualZeroConfidenceTime = 300     -- Zero visual confidence after this time (5 minutes)

-- Weight factors for intel confidence calculation (should sum to 1.0)
iVisualWeight = 0.40                -- Weight of visual/scout recency
iRadarWeight = 0.30                 -- Weight of radar coverage
iOmniWeight = 0.30                  -- Weight of omni coverage

-- Intel confidence thresholds
iHighConfidenceThreshold = 70       -- >= this is HIGH confidence
iMediumConfidenceThreshold = 40     -- >= this is MEDIUM confidence (below is LOW)

-- Scouting priority boost factors
iArmyProximityScoutBoost = 50       -- Boost to scouting priority for zones near armies
iArmyDestinationScoutBoost = 80     -- Boost for zones armies are moving towards
iLowIntelUrgentThreshold = 25       -- Below this triggers urgent scouting requests

-- Movement caution factors
iCautionSpeedReduction = 0.7        -- Move at 70% aggression in medium-intel zones
iLowIntelWaitThreshold = 20         -- Below this, consider waiting for intel before moving

-- Reference strings for zone data
refiIntelConfidence = 'IntConf'              -- Intel confidence score (0-100)
refiTimeLastIntelUpdate = 'IntUpdTm'         -- When confidence was last calculated
refbNeedsUrgentScouting = 'IntUrgSc'         -- True if zone needs urgent scouting
refiArmyProximityBoost = 'IntArmPrx'         -- Boost from nearby friendly armies

-- Intel confidence levels
refiIntelHigh = 1
refiIntelMedium = 2
refiIntelLow = 3

-- Threat type references for threat-specific intel tracking
refiThreatTypeLand = 1
refiThreatTypeAir = 2
refiThreatTypeNaval = 3
refiThreatTypeExperimental = 4
refiThreatTypeNavalSubmersible = 5

-- Mobility-based decay factors (faster decay for more mobile threats)
iMobilityDecayFactorStatic = 0.5      -- Structures decay intel slowly
iMobilityDecayFactorSlow = 1.0        -- T1/T2 land units
iMobilityDecayFactorFast = 1.5        -- Fast units (air, fast land)
iMobilityDecayFactorExperimental = 0.8 -- Large experimentals (easier to track)

-- Intel surprise detection thresholds
iSurpriseThreatThreshold = 500        -- Threat appearing suddenly triggers surprise
iSurpriseConfidenceThreshold = 60     -- Below this confidence, expect surprises
iSurpriseRecencySeconds = 10          -- How recent intel must be to avoid surprise

-- Zone threat type tracking references
refiLastKnownLandThreat = 'IntLndThr'
refiLastKnownAirThreat = 'IntAirThr'
refiLastKnownNavalThreat = 'IntNavThr'
refiLastKnownExperimentalThreat = 'IntExpThr'
refiLastKnownNavalSubmersibleThreat = 'IntSubThr' -- Submarine-specific threat tracking
refiTimeLastThreatUpdate = 'IntThrUpd'
refbIntelSurpriseDetected = 'IntSurp'
refiSurpriseThreatAmount = 'IntSurpAmt'
refiTimeLastIntelSurprise = 'IntSurpTm'

--===========================================
-- CORE INTEL CONFIDENCE FUNCTIONS
--===========================================

---Calculate the visual confidence score based on time since last visual
---@param iTimeSinceVisual number Seconds since zone was last visually scouted
---@return number Visual confidence score (0-100)
function GetVisualConfidenceScore(iTimeSinceVisual)
    if iTimeSinceVisual <= iVisualFullConfidenceTime then
        return 100
    elseif iTimeSinceVisual >= iVisualZeroConfidenceTime then
        return 0
    else
        -- Linear decay between full and zero confidence times
        local iDecayRange = iVisualZeroConfidenceTime - iVisualFullConfidenceTime
        local iTimeInDecay = iTimeSinceVisual - iVisualFullConfidenceTime
        return math.max(0, 100 - (iTimeInDecay / iDecayRange) * 100)
    end
end

---Calculate overall intel confidence for a zone
---@param tLZOrWZTeamData table Zone team data containing intel tracking values
---@param iTeam number Team index
---@return number Intel confidence score (0-100)
function GetCoverageConfidence(iCoverage)
    -- Coverage is the distance from a zone midpoint to a sensor's edge.
    return math.max(0, math.min(100, (iCoverage or 0) * 2))
end

function CalculateIntelConfidence(tLZOrWZTeamData, iTeam)
    local sFunctionRef = 'CalculateIntelConfidence'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iCurrentTime = GetGameTimeSeconds()
    
    -- Get time since last visual
    local iTimeLastVisual = tLZOrWZTeamData[M28Map.refiTimeLastHadVisual]
    local iTimeSinceVisual = iTimeLastVisual and iCurrentTime - iTimeLastVisual or iVisualZeroConfidenceTime
    local iVisualScore = GetVisualConfidenceScore(iTimeSinceVisual)
    
    -- Convert operational coverage distances to bounded confidence scores.
    local iRadarScore = GetCoverageConfidence(tLZOrWZTeamData[M28Map.refiRadarCoverage])
    local iOmniScore = GetCoverageConfidence(tLZOrWZTeamData[M28Map.refiOmniCoverage])
    
    -- Calculate weighted confidence
    local iConfidence = (iVisualScore * iVisualWeight) + 
                        (iRadarScore * iRadarWeight) + 
                        (iOmniScore * iOmniWeight)
    
    -- Clamp to 0-100 range
    iConfidence = math.max(iOmniScore, math.min(100, iConfidence))
    
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
    return iConfidence
end

---Get the intel confidence level category (HIGH, MEDIUM, LOW)
---@param iConfidence number Intel confidence score (0-100)
---@return number Intel level (refiIntelHigh, refiIntelMedium, or refiIntelLow)
function GetIntelConfidenceLevel(iConfidence)
    if iConfidence >= iHighConfidenceThreshold then
        return refiIntelHigh
    elseif iConfidence >= iMediumConfidenceThreshold then
        return refiIntelMedium
    else
        return refiIntelLow
    end
end

---Check if a zone has sufficient intel for aggressive movement
---@param tLZOrWZTeamData table Zone team data
---@param iTeam number Team index
---@param bRequireHighConfidence boolean If true, require HIGH confidence; otherwise MEDIUM is acceptable
---@return boolean True if intel is sufficient for movement
function HasSufficientIntelForMovement(tLZOrWZTeamData, iTeam, bRequireHighConfidence)
    local iConfidence = CalculateIntelConfidence(tLZOrWZTeamData, iTeam)
    if bRequireHighConfidence then
        return iConfidence >= iHighConfidenceThreshold
    else
        return iConfidence >= iMediumConfidenceThreshold
    end
end

---Check if a zone needs urgent scouting (low intel + relevant to operations)
---@param tLZOrWZTeamData table Zone team data
---@param iTeam number Team index
---@param bNearFriendlyArmy boolean True if friendly army is near or moving to this zone
---@return boolean True if zone needs urgent scouting
function NeedsUrgentScouting(tLZOrWZTeamData, iTeam, bNearFriendlyArmy)
    local iConfidence = CalculateIntelConfidence(tLZOrWZTeamData, iTeam)
    
    -- Urgent if low confidence AND relevant to army operations
    if iConfidence < iLowIntelUrgentThreshold and bNearFriendlyArmy then
        return true
    end
    
    -- Also urgent if very low confidence and has enemy threat history
    if iConfidence < 15 and (tLZOrWZTeamData[M28Map.subrefTThreatEnemyCombatTotal] or 0) > 0 then
        return true
    end
    
    return false
end

--===========================================
-- ZONE INTEL REFRESH FUNCTIONS
--===========================================

---Refresh intel confidence for all land zones for a team
---@param iTeam number Team index
function RefreshAllLandZoneIntelConfidence(iTeam)
    local sFunctionRef = 'RefreshAllLandZoneIntelConfidence'
    local bDebugMessages, tDebugContext = M28Profiler.GetDebugControl(M28Profiler.refDebugChannelIntel, sFunctionRef)
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iCurrentTime = GetGameTimeSeconds()

    for iPlateau, tPlateauSubtable in M28Map.tAllPlateaus do
        if M28Utilities.IsTableEmpty(tPlateauSubtable[M28Map.subrefPlateauLandZones]) == false then
            for iLandZone, tLZData in tPlateauSubtable[M28Map.subrefPlateauLandZones] do
                local tLZTeamData = tLZData[M28Map.subrefLZTeamData][iTeam]
                if tLZTeamData then
                    -- Calculate and store intel confidence
                    local iConfidence = CalculateIntelConfidence(tLZTeamData, iTeam)
                    tLZTeamData[refiIntelConfidence] = iConfidence
                    tLZTeamData[refiTimeLastIntelUpdate] = iCurrentTime

                    if bDebugMessages == true then
                        LOG(sFunctionRef..': P'..iPlateau..'Z'..iLandZone..' intel confidence='..iConfidence)
                    end
                end
            end
        end
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

---Refresh intel confidence for all water zones for a team
---@param iTeam number Team index
function RefreshAllWaterZoneIntelConfidence(iTeam)
    local sFunctionRef = 'RefreshAllWaterZoneIntelConfidence'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iCurrentTime = GetGameTimeSeconds()

    for iPond, tPondSubtable in M28Map.tPondDetails do
        if M28Utilities.IsTableEmpty(tPondSubtable[M28Map.subrefPondWaterZones]) == false then
            for iWaterZone, tWZData in tPondSubtable[M28Map.subrefPondWaterZones] do
                local tWZTeamData = tWZData[M28Map.subrefWZTeamData][iTeam]
                if tWZTeamData then
                    local iConfidence = CalculateIntelConfidence(tWZTeamData, iTeam)
                    tWZTeamData[refiIntelConfidence] = iConfidence
                    tWZTeamData[refiTimeLastIntelUpdate] = iCurrentTime
                end
            end
        end
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

---Get cached intel confidence for a zone, or calculate if stale
---@param tLZOrWZTeamData table Zone team data
---@param iTeam number Team index
---@param iMaxAge number Maximum age in seconds before recalculating
---@return number Intel confidence score (0-100)
function GetZoneIntelConfidence(tLZOrWZTeamData, iTeam, iMaxAge)
    local iCurrentTime = GetGameTimeSeconds()
    local iLastUpdate = tLZOrWZTeamData[refiTimeLastIntelUpdate] or 0

    if iCurrentTime - iLastUpdate > (iMaxAge or 1) then
        -- Recalculate if stale
        local iConfidence = CalculateIntelConfidence(tLZOrWZTeamData, iTeam)
        tLZOrWZTeamData[refiIntelConfidence] = iConfidence
        tLZOrWZTeamData[refiTimeLastIntelUpdate] = iCurrentTime
        return iConfidence
    else
        return tLZOrWZTeamData[refiIntelConfidence] or 0
    end
end

--===========================================
-- ARMY-AWARE SCOUTING FUNCTIONS
--===========================================

---Get zones that need urgent scouting near friendly army positions
---@param iTeam number Team index
---@param iMaxZones number Maximum number of zones to return
---@return table Array of {iPlateau, iLandZone, iUrgency} for zones needing scouts
function GetZonesNeedingArmyScouting(iTeam, iMaxZones)
    local sFunctionRef = 'GetZonesNeedingArmyScouting'
    local bDebugMessages, tDebugContext = M28Profiler.GetDebugControl(M28Profiler.refDebugChannelIntel, sFunctionRef)
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local tUrgentZones = {}
    local iCurrentTime = GetGameTimeSeconds()

    -- Find zones with friendly combat units
    local tiZonesWithArmies = {}
    for iPlateau, tPlateauSubtable in M28Map.tAllPlateaus do
        if M28Utilities.IsTableEmpty(tPlateauSubtable[M28Map.subrefPlateauLandZones]) == false then
            for iLandZone, tLZData in tPlateauSubtable[M28Map.subrefPlateauLandZones] do
                local tLZTeamData = tLZData[M28Map.subrefLZTeamData][iTeam]
                if tLZTeamData and (tLZTeamData[M28Map.subrefLZTThreatAllyCombatTotal] or 0) > 100 then
                    tiZonesWithArmies[iPlateau..'-'..iLandZone] = {iPlateau, iLandZone}
                end
            end
        end
    end

    -- Check adjacent zones of army positions for low intel
    for sZoneKey, tZoneRef in tiZonesWithArmies do
        local iPlateau = tZoneRef[1]
        local iLandZone = tZoneRef[2]
        local tLZData = M28Map.tAllPlateaus[iPlateau][M28Map.subrefPlateauLandZones][iLandZone]

        -- Check adjacent zones
        if M28Utilities.IsTableEmpty(tLZData[M28Map.subrefLZAdjacentLandZones]) == false then
            for _, iAdjLZ in tLZData[M28Map.subrefLZAdjacentLandZones] do
                local tAdjLZData = M28Map.tAllPlateaus[iPlateau][M28Map.subrefPlateauLandZones][iAdjLZ]
                local tAdjLZTeamData = tAdjLZData[M28Map.subrefLZTeamData][iTeam]

                if tAdjLZTeamData then
                    local iConfidence = GetZoneIntelConfidence(tAdjLZTeamData, iTeam, 2)

                    -- Priority boost for zones adjacent to armies with low intel
                    if iConfidence < iMediumConfidenceThreshold then
                        local iUrgency = (iMediumConfidenceThreshold - iConfidence) + iArmyProximityScoutBoost

                        -- Extra urgency if enemy was previously seen here
                        if (tAdjLZTeamData[M28Map.subrefTThreatEnemyCombatTotal] or 0) > 0 then
                            iUrgency = iUrgency + 30
                        end

                        table.insert(tUrgentZones, {iPlateau, iAdjLZ, iUrgency})
                        if bDebugMessages == true then
                            LOG(sFunctionRef..': Zone P'..iPlateau..'Z'..iAdjLZ..' needs scouting, urgency='..iUrgency)
                        end
                    end
                end
            end
        end
    end

    -- Sort by urgency (descending)
    table.sort(tUrgentZones, function(a, b) return a[3] > b[3] end)

    -- Return top N zones
    local tResult = {}
    for i = 1, math.min(iMaxZones or 5, table.getn(tUrgentZones)) do
        table.insert(tResult, tUrgentZones[i])
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
    return tResult
end

--===========================================
-- MOVEMENT CAUTION FUNCTIONS
--===========================================

---Get movement caution factor based on intel confidence
---@param tLZOrWZTeamData table Zone team data
---@param iTeam number Team index
---@return number Caution factor (1.0 = normal, <1.0 = more cautious)
function GetMovementCautionFactor(tLZOrWZTeamData, iTeam)
    local iConfidence = GetZoneIntelConfidence(tLZOrWZTeamData, iTeam, 2)
    local iLevel = GetIntelConfidenceLevel(iConfidence)

    if iLevel == refiIntelHigh then
        return 1.0  -- Full aggression
    elseif iLevel == refiIntelMedium then
        return iCautionSpeedReduction  -- Reduced aggression
    else
        return 0.5  -- Very cautious
    end
end

---Check if army should wait for intel before moving to a zone
---@param tDestLZTeamData table Destination zone team data
---@param iTeam number Team index
---@param iOurThreat number Our army threat level
---@return boolean True if should wait for scouting first
function ShouldWaitForIntel(tDestLZTeamData, iTeam, iOurThreat)
    local iConfidence = GetZoneIntelConfidence(tDestLZTeamData, iTeam, 2)

    -- If confidence is very low, wait for intel
    if iConfidence < iLowIntelWaitThreshold then
        -- Exception: if our threat is overwhelming, proceed anyway
        local iLastKnownEnemyThreat = tDestLZTeamData[M28Map.subrefTThreatEnemyCombatTotal] or 0
        if iOurThreat > iLastKnownEnemyThreat * 3 and iLastKnownEnemyThreat < 500 then
            return false  -- Proceed with overwhelming force
        end
        return true
    end

    return false
end

---Calculate safe buffer distance based on intel confidence
---@param tLZOrWZTeamData table Zone team data
---@param iTeam number Team index
---@param iBaseBuffer number Base buffer distance
---@return number Adjusted buffer distance
function GetIntelAwareBufferDistance(tLZOrWZTeamData, iTeam, iBaseBuffer)
    local iConfidence = GetZoneIntelConfidence(tLZOrWZTeamData, iTeam, 2)
    local iLevel = GetIntelConfidenceLevel(iConfidence)

    if iLevel == refiIntelHigh then
        return iBaseBuffer
    elseif iLevel == refiIntelMedium then
        return iBaseBuffer * 1.3  -- 30% larger buffer
    else
        return iBaseBuffer * 1.6  -- 60% larger buffer for low intel
    end
end

---Request priority scouting for a zone (called when army needs intel)
---@param iPlateau number Plateau number (0 for water zone)
---@param iLandOrWaterZone number Zone number
---@param iTeam number Team index
---@param iUrgency number Urgency level (higher = more urgent)
---@param bUseExistingScoutsOnly boolean Optional; route scouts without requesting additional production
function RequestPriorityScoutingForZone(iPlateau, iLandOrWaterZone, iTeam, iUrgency, bUseExistingScoutsOnly)
    iUrgency = iUrgency or 50
    local sFunctionRef = 'RequestPriorityScoutingForZone'
    local bDebugMessages, tDebugContext = M28Profiler.GetDebugControl(M28Profiler.refDebugChannelIntel, sFunctionRef)
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    -- Store in team data for air scouts to pick up
    if not(M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones]) then
        M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones] = {}
    end

    local tZoneRequest = {
        iPlateau = iPlateau,
        iZone = iLandOrWaterZone,
        iUrgency = iUrgency or 50,
        iTimeRequested = GetGameTimeSeconds(),
        bUseExistingScoutsOnly = bUseExistingScoutsOnly == true
    }

    -- Check if already in list
    local bAlreadyRequested = false
    for iEntry, tExisting in M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones] do
        if tExisting.iPlateau == iPlateau and tExisting.iZone == iLandOrWaterZone then
            tExisting.iUrgency = math.max(iUrgency, tExisting.iUrgency)
            tExisting.iTimeRequested = GetGameTimeSeconds()
            tExisting.bUseExistingScoutsOnly = tExisting.bUseExistingScoutsOnly and bUseExistingScoutsOnly == true
            bAlreadyRequested = true
            break
        end
    end

    if not(bAlreadyRequested) then
        table.insert(M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones], tZoneRequest)
        if bDebugMessages == true then
            LOG(sFunctionRef..': Added priority scout request for P'..iPlateau..'Z'..iLandOrWaterZone..' with urgency='..iUrgency)
        end
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

---Get and clear priority scout zone requests for air scout assignment
---@param iTeam number Team index
---@return table Array of zone requests sorted by urgency
function GetPriorityScoutZoneRequests(iTeam)
    local sFunctionRef = 'GetPriorityScoutZoneRequests'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local tRequests = M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones] or {}
    local iCurrentTime = GetGameTimeSeconds()

    -- Remove stale requests (older than 30 seconds)
    local tValidRequests = {}
    for iEntry, tRequest in tRequests do
        local tZoneData, tZoneTeamData
        if tRequest.iPlateau > 0 then
            tZoneData = M28Map.tAllPlateaus[tRequest.iPlateau][M28Map.subrefPlateauLandZones][tRequest.iZone]
            tZoneTeamData = tZoneData[M28Map.subrefLZTeamData][iTeam]
        else
            tZoneData = M28Map.tPondDetails[M28Map.tiPondByWaterZone[tRequest.iZone]][M28Map.subrefPondWaterZones][tRequest.iZone]
            tZoneTeamData = tZoneData[M28Map.subrefWZTeamData][iTeam]
        end
        local iLastVisual = tZoneTeamData[M28Map.refiTimeLastHadVisual] or -100
        if iCurrentTime - tRequest.iTimeRequested < 30 and iCurrentTime - iLastVisual > 10 then
            table.insert(tValidRequests, tRequest)
        end
    end

    -- Sort by urgency
    table.sort(tValidRequests, function(a, b)
        if a.iUrgency ~= b.iUrgency then return a.iUrgency > b.iUrgency end
        if a.iPlateau ~= b.iPlateau then return a.iPlateau < b.iPlateau end
        return a.iZone < b.iZone
    end)

    -- Store cleaned list back
    M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones] = tValidRequests

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
    return tValidRequests
end

--===========================================
-- MOBILITY-BASED INTEL DECAY
--===========================================

---Get decay factor based on threat type (mobile threats require more frequent scouting)
---@param iThreatType number Threat type (refiThreatTypeLand, refiThreatTypeAir, etc.)
---@return number Decay factor multiplier
function GetMobilityDecayFactor(iThreatType)
    if iThreatType == refiThreatTypeAir then
        return iMobilityDecayFactorFast
    elseif iThreatType == refiThreatTypeNaval then
        return iMobilityDecayFactorSlow
    elseif iThreatType == refiThreatTypeExperimental then
        return iMobilityDecayFactorExperimental
    elseif iThreatType == refiThreatTypeLand then
        return iMobilityDecayFactorSlow
    else
        return 1.0
    end
end

---Calculate mobility-adjusted visual confidence (faster decay for mobile threats)
---@param iTimeSinceVisual number Seconds since zone was last visually scouted
---@param iThreatType number Threat type for mobility adjustment
---@return number Visual confidence score adjusted for mobility (0-100)
function GetMobilityAdjustedVisualConfidence(iTimeSinceVisual, iThreatType)
    local iDecayFactor = GetMobilityDecayFactor(iThreatType)
    local iAdjustedTime = iTimeSinceVisual * iDecayFactor
    return GetVisualConfidenceScore(iAdjustedTime)
end

--===========================================
-- THREAT TYPE SPECIFIC TRACKING
--===========================================

---Update threat type tracking for a zone (single threat type version)
---@param tLZOrWZTeamData table Zone team data
---@param iThreatType number Threat type constant (e.g., refiThreatTypeLand)
---@param iThreatValue number Current known threat value
function UpdateThreatTypeTracking(tLZOrWZTeamData, iThreatType, iThreatValue)
    local iCurrentTime = GetGameTimeSeconds()

    -- Map threat type to the appropriate reference
    if iThreatType == refiThreatTypeLand then
        tLZOrWZTeamData[refiLastKnownLandThreat] = iThreatValue or 0
    elseif iThreatType == refiThreatTypeAir then
        tLZOrWZTeamData[refiLastKnownAirThreat] = iThreatValue or 0
    elseif iThreatType == refiThreatTypeNaval then
        tLZOrWZTeamData[refiLastKnownNavalThreat] = iThreatValue or 0
    elseif iThreatType == refiThreatTypeExperimental then
        tLZOrWZTeamData[refiLastKnownExperimentalThreat] = iThreatValue or 0
    elseif iThreatType == refiThreatTypeNavalSubmersible then
        tLZOrWZTeamData[refiLastKnownNavalSubmersibleThreat] = iThreatValue or 0
    end
    tLZOrWZTeamData[refiTimeLastThreatUpdate] = iCurrentTime
end

---Update all threat type tracking for a zone at once
---@param tLZOrWZTeamData table Zone team data
---@param iLandThreat number Current known land threat
---@param iAirThreat number Current known air threat
---@param iNavalThreat number Current known naval threat
---@param iExpThreat number Current known experimental threat
function UpdateAllThreatTypeTracking(tLZOrWZTeamData, iLandThreat, iAirThreat, iNavalThreat, iExpThreat)
    local iCurrentTime = GetGameTimeSeconds()

    tLZOrWZTeamData[refiLastKnownLandThreat] = iLandThreat or 0
    tLZOrWZTeamData[refiLastKnownAirThreat] = iAirThreat or 0
    tLZOrWZTeamData[refiLastKnownNavalThreat] = iNavalThreat or 0
    tLZOrWZTeamData[refiLastKnownExperimentalThreat] = iExpThreat or 0
    tLZOrWZTeamData[refiTimeLastThreatUpdate] = iCurrentTime
end

---Get intel confidence for a specific threat type
---@param tLZOrWZTeamData table Zone team data
---@param iTeam number Team index
---@param iThreatType number Threat type to check
---@return number Intel confidence adjusted for that threat type's mobility
function GetThreatTypeIntelConfidence(tLZOrWZTeamData, iTeam, iThreatType)
    local iCurrentTime = GetGameTimeSeconds()
    local iTimeLastVisual = tLZOrWZTeamData[M28Map.refiTimeLastHadVisual]
    local iTimeSinceVisual = iTimeLastVisual and iCurrentTime - iTimeLastVisual or iVisualZeroConfidenceTime

    -- Get mobility-adjusted visual score
    local iVisualScore = GetMobilityAdjustedVisualConfidence(iTimeSinceVisual, iThreatType)

    -- Radar and omni remain the same
    local iRadarScore = GetCoverageConfidence(tLZOrWZTeamData[M28Map.refiRadarCoverage])
    local iOmniScore = GetCoverageConfidence(tLZOrWZTeamData[M28Map.refiOmniCoverage])

    local iConfidence = (iVisualScore * iVisualWeight) +
                        (iRadarScore * iRadarWeight) +
                        (iOmniScore * iOmniWeight)

    return math.max(iOmniScore, math.min(100, iConfidence))
end

--===========================================
-- INTEL SURPRISE DETECTION
--===========================================

---Check for intel surprise (unexpected units appearing in supposedly-scouted area)
---@param tLZOrWZTeamData table Zone team data
---@param iTeam number Team index
---@param iActualThreat number Actual threat just discovered
---@param iPreviousKnownThreat number What we thought the threat was
---@return boolean True if this constitutes an intel surprise
function DetectIntelSurprise(tLZOrWZTeamData, iTeam, iActualThreat, iPreviousKnownThreat)
    local sFunctionRef = 'DetectIntelSurprise'
    local bDebugMessages, tDebugContext = M28Profiler.GetDebugControl(M28Profiler.refDebugChannelIntel, sFunctionRef)

    local iCurrentTime = GetGameTimeSeconds()
    local iConfidence = GetZoneIntelConfidence(tLZOrWZTeamData, iTeam, 2)

    -- Calculate threat difference
    local iThreatDifference = iActualThreat - (iPreviousKnownThreat or 0)

    -- Surprise if significant new threat appears and we thought we had good intel
    if iThreatDifference >= iSurpriseThreatThreshold and iConfidence >= iSurpriseConfidenceThreshold then
        tLZOrWZTeamData[refbIntelSurpriseDetected] = true
        tLZOrWZTeamData[refiSurpriseThreatAmount] = iThreatDifference
        tLZOrWZTeamData[refiTimeLastIntelSurprise] = iCurrentTime

        if bDebugMessages == true then
            LOG(sFunctionRef..': INTEL SURPRISE! Expected threat='..(iPreviousKnownThreat or 0)..
                ' but found='..iActualThreat..' (diff='..iThreatDifference..
                ') despite confidence='..iConfidence)
        end
        return true
    end

    if iCurrentTime - (tLZOrWZTeamData[refiTimeLastIntelSurprise] or -100) > iSurpriseRecencySeconds then
        tLZOrWZTeamData[refbIntelSurpriseDetected] = false
        tLZOrWZTeamData[refiSurpriseThreatAmount] = 0
    end
    return false
end

---Check if zone recently had an intel surprise
---@param tLZOrWZTeamData table Zone team data
---@return boolean True if zone had recent intel surprise
function HadRecentIntelSurprise(tLZOrWZTeamData)
    return tLZOrWZTeamData[refbIntelSurpriseDetected] == true
        and GetGameTimeSeconds() - (tLZOrWZTeamData[refiTimeLastIntelSurprise] or -100) <= iSurpriseRecencySeconds
end

---Get the amount of surprise threat that appeared
---@param tLZOrWZTeamData table Zone team data
---@return number Amount of unexpected threat
function GetSurpriseThreatAmount(tLZOrWZTeamData)
    return tLZOrWZTeamData[refiSurpriseThreatAmount] or 0
end

--===========================================
-- BATTLE CONCLUDED DETECTION
--===========================================

-- References for battle concluded tracking
refiPeakEnemyThreat = 'IntPeakEnThr'
refiTimePeakThreat = 'IntPeakThrTm'
refbBattleConcluded = 'IntBatConc'
refiTimeBattleConcluded = 'IntBatConcTm'

-- Thresholds for battle concluded detection
iBattleConcludedThreatDropPercent = 0.25  -- Enemy threat dropped to 25% of peak = battle concluded
iBattleConcludedMinPeakThreat = 500       -- Minimum peak threat to consider it a battle
iBattleConcludedRecencySeconds = 30       -- How long battle concluded status lasts

---Update peak enemy threat tracking for a zone
---@param tLZOrWZTeamData table Zone team data
---@param iCurrentEnemyThreat number Current enemy combat threat in zone
function UpdatePeakThreatTracking(tLZOrWZTeamData, iCurrentEnemyThreat)
    local iCurrentTime = GetGameTimeSeconds()
    local iPeakThreat = tLZOrWZTeamData[refiPeakEnemyThreat] or 0

    -- Update peak if current threat is higher
    if iCurrentEnemyThreat > iPeakThreat then
        tLZOrWZTeamData[refiPeakEnemyThreat] = iCurrentEnemyThreat
        tLZOrWZTeamData[refiTimePeakThreat] = iCurrentTime
    -- Decay peak threat over time if no new peak (prevents stale peaks)
    elseif iCurrentTime - (tLZOrWZTeamData[refiTimePeakThreat] or 0) > 60 then
        -- Decay peak by 10% per minute
        local iElapsed = iCurrentTime - (tLZOrWZTeamData[refiTimePeakThreat] or 0)
        tLZOrWZTeamData[refiPeakEnemyThreat] = iPeakThreat * math.pow(0.9, iElapsed / 60)
        tLZOrWZTeamData[refiTimePeakThreat] = iCurrentTime
    end
end

---Check if a battle has concluded in a zone (enemy threat dropped significantly)
---@param tLZOrWZTeamData table Zone team data
---@param iCurrentEnemyThreat number Current enemy combat threat in zone
---@return boolean True if battle has concluded (enemy threat dropped significantly)
function DetectBattleConcluded(tLZOrWZTeamData, iCurrentEnemyThreat)
    local sFunctionRef = 'DetectBattleConcluded'
    local bDebugMessages, tDebugContext = M28Profiler.GetDebugControl(M28Profiler.refDebugChannelIntel, sFunctionRef)

    local iCurrentTime = GetGameTimeSeconds()
    local iPeakThreat = tLZOrWZTeamData[refiPeakEnemyThreat] or 0

    -- Update peak tracking
    UpdatePeakThreatTracking(tLZOrWZTeamData, iCurrentEnemyThreat)

    -- Losing contacts is not evidence that the opposing army was destroyed.
    local iLastVisual = tLZOrWZTeamData[M28Map.refiTimeLastHadVisual] or -100
    local bCovered = (tLZOrWZTeamData[M28Map.refiRadarCoverage] or 0) >= 50
        or (tLZOrWZTeamData[M28Map.refiOmniCoverage] or 0) >= 50
        or iCurrentTime - iLastVisual <= 5
    if not(bCovered) then
        tLZOrWZTeamData[refbBattleConcluded] = false
        return false
    end
    if iPeakThreat >= iBattleConcludedMinPeakThreat then
        local iThreatRatio = iCurrentEnemyThreat / iPeakThreat
        if iThreatRatio <= iBattleConcludedThreatDropPercent then
            -- Battle concluded - enemy threat dropped to 25% or less of peak
            tLZOrWZTeamData[refbBattleConcluded] = true
            tLZOrWZTeamData[refiTimeBattleConcluded] = iCurrentTime

            if bDebugMessages == true then
                LOG(sFunctionRef..': BATTLE CONCLUDED! Peak threat='..iPeakThreat..
                    ' Current threat='..iCurrentEnemyThreat..' Ratio='..string.format('%.2f', iThreatRatio))
            end
            return true
        end
    end

    -- Clear battle concluded flag if threat has risen again
    if iCurrentEnemyThreat > iPeakThreat * 0.5 then
        tLZOrWZTeamData[refbBattleConcluded] = false
    end

    return false
end

---Check if zone recently had a battle conclude
---@param tLZOrWZTeamData table Zone team data
---@return boolean True if battle concluded recently
function HasRecentBattleConcluded(tLZOrWZTeamData)
    local iCurrentTime = GetGameTimeSeconds()
    local iTimeConcluded = tLZOrWZTeamData[refiTimeBattleConcluded] or 0

    if tLZOrWZTeamData[refbBattleConcluded] == true then
        -- Check if still within recency window
        if iCurrentTime - iTimeConcluded <= iBattleConcludedRecencySeconds then
            return true
        end
    end
    return false
end

---Get the peak enemy threat that was recorded in a zone
---@param tLZOrWZTeamData table Zone team data
---@return number Peak enemy threat value
function GetPeakEnemyThreat(tLZOrWZTeamData)
    return tLZOrWZTeamData[refiPeakEnemyThreat] or 0
end

--===========================================
-- NAVAL ZONE INTEL FUNCTIONS
--===========================================

---Get water zones needing urgent scouting near friendly naval forces
---@param iTeam number Team index
---@param iMaxZones number Maximum number of zones to return
---@return table Array of {iPond, iWaterZone, iUrgency} for zones needing scouts
function GetWaterZonesNeedingNavyScouting(iTeam, iMaxZones)
    local sFunctionRef = 'GetWaterZonesNeedingNavyScouting'
    local bDebugMessages, tDebugContext = M28Profiler.GetDebugControl(M28Profiler.refDebugChannelIntel, sFunctionRef)
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local tUrgentZones = {}

    -- Find water zones with friendly naval units
    local tiZonesWithNavy = {}
    for iPond, tPondSubtable in M28Map.tPondDetails do
        if M28Utilities.IsTableEmpty(tPondSubtable[M28Map.subrefPondWaterZones]) == false then
            for iWaterZone, tWZData in tPondSubtable[M28Map.subrefPondWaterZones] do
                local tWZTeamData = tWZData[M28Map.subrefWZTeamData][iTeam]
                if tWZTeamData and (tWZTeamData[M28Map.subrefWZTThreatAllyCombatTotal] or 0) > 50 then
                    tiZonesWithNavy[iPond..'-'..iWaterZone] = {iPond, iWaterZone}
                end
            end
        end
    end

    -- Check adjacent water zones for low intel
    for sZoneKey, tZoneRef in tiZonesWithNavy do
        local iPond = tZoneRef[1]
        local iWaterZone = tZoneRef[2]
        local tWZData = M28Map.tPondDetails[iPond][M28Map.subrefPondWaterZones][iWaterZone]

        -- Check adjacent water zones
        if tWZData and M28Utilities.IsTableEmpty(tWZData[M28Map.subrefWZAdjacentWaterZones]) == false then
            for _, iAdjWZ in tWZData[M28Map.subrefWZAdjacentWaterZones] do
                local tAdjWZData = M28Map.tPondDetails[iPond][M28Map.subrefPondWaterZones][iAdjWZ]
                if tAdjWZData then
                    local tAdjWZTeamData = tAdjWZData[M28Map.subrefWZTeamData][iTeam]

                    if tAdjWZTeamData then
                        local iConfidence = GetZoneIntelConfidence(tAdjWZTeamData, iTeam, 2)

                        if iConfidence < iMediumConfidenceThreshold then
                            local iUrgency = (iMediumConfidenceThreshold - iConfidence) + iArmyProximityScoutBoost

                            -- Extra urgency if enemy was previously seen here
                            if (tAdjWZTeamData[M28Map.subrefTThreatEnemyCombatTotal] or 0) > 0 then
                                iUrgency = iUrgency + 30
                            end

                            table.insert(tUrgentZones, {iPond, iAdjWZ, iUrgency})
                            if bDebugMessages == true then
                                LOG(sFunctionRef..': Water zone Pond'..iPond..'WZ'..iAdjWZ..' needs scouting, urgency='..iUrgency)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Sort by urgency (descending)
    table.sort(tUrgentZones, function(a, b) return a[3] > b[3] end)

    -- Return top N zones
    local tResult = {}
    for i = 1, math.min(iMaxZones or 5, table.getn(tUrgentZones)) do
        table.insert(tResult, tUrgentZones[i])
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
    return tResult
end

---Request priority air scouting over a water zone
---@param iPond number Pond number
---@param iWaterZone number Water zone number
---@param iTeam number Team index
---@param iUrgency number Urgency level
function RequestPriorityNavalScouting(iPond, iWaterZone, iTeam, iUrgency)
    -- Use plateau 0 to indicate water zone in the priority scout system
    RequestPriorityScoutingForZone(0, iWaterZone, iTeam, iUrgency)
end

--===========================================
-- AIR SCOUT PRODUCTION SCALING
--===========================================

-- Configuration for dynamic air scout production
iMinAirScouts = 2                   -- Minimum air scouts to maintain
iMaxAirScouts = 12                  -- Maximum air scouts to produce
iZonesPerScout = 3                  -- How many zones needing scouting per additional scout
iPriorityZoneScoutWeight = 2        -- Priority zones count as this many regular zones

---Count the total number of zones that need scouting for a team
---This includes both land zones with low intel and priority scout requests
---@param iTeam number Team index
---@return number Total count of zones needing scouting (weighted)
---@return number Count of priority scout zones
---@return number Count of low intel land zones
---@return number Count of low intel water zones
function GetZonesNeedingScoutingCount(iTeam)
    local sFunctionRef = 'GetZonesNeedingScoutingCount'
    local bDebugMessages, tDebugContext = M28Profiler.GetDebugControl(M28Profiler.refDebugChannelIntel, sFunctionRef)
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iPriorityZoneCount = 0
    local iLowIntelLandZones = 0
    local iLowIntelWaterZones = 0

    -- Count priority scout requests
    local tRequests = GetPriorityScoutZoneRequests(iTeam)
    if tRequests then
        for _, tRequest in tRequests do
            -- Routine coverage redirects scouts; combat requests can also fund replacements.
            if not(tRequest.bUseExistingScoutsOnly) then iPriorityZoneCount = iPriorityZoneCount + 1 end
        end
    end

    -- Count land zones with low intel confidence
    for iPlateau, tPlateauSubtable in M28Map.tAllPlateaus do
        if M28Utilities.IsTableEmpty(tPlateauSubtable[M28Map.subrefPlateauLandZones]) == false then
            for iLandZone, tLZData in tPlateauSubtable[M28Map.subrefPlateauLandZones] do
                local tLZTeamData = tLZData[M28Map.subrefLZTeamData][iTeam]
                if tLZTeamData then
                    local iConfidence = GetZoneIntelConfidence(tLZTeamData, iTeam, 5)
                    if GetIntelConfidenceLevel(iConfidence) == refiIntelLow and
                            ((tLZTeamData[M28Map.subrefLZThreatAllyMobileDFTotal] or 0) > 0 or tLZTeamData[M28Map.subrefbEnemiesInThisOrAdjacentLZ]) then
                        iLowIntelLandZones = iLowIntelLandZones + 1
                    end
                end
            end
        end
    end

    -- Count water zones with low intel confidence
    for iPond, tPondSubtable in M28Map.tPondDetails do
        if M28Utilities.IsTableEmpty(tPondSubtable[M28Map.subrefPondWaterZones]) == false then
            for iWaterZone, tWZData in tPondSubtable[M28Map.subrefPondWaterZones] do
                local tWZTeamData = tWZData[M28Map.subrefWZTeamData][iTeam]
                if tWZTeamData then
                    local iConfidence = GetZoneIntelConfidence(tWZTeamData, iTeam, 5)
                    if GetIntelConfidenceLevel(iConfidence) == refiIntelLow and
                            ((tWZTeamData[M28Map.subrefWZTThreatAllyCombatTotal] or 0) > 0 or tWZTeamData[M28Map.subrefbEnemiesInThisOrAdjacentWZ]) then
                        iLowIntelWaterZones = iLowIntelWaterZones + 1
                    end
                end
            end
        end
    end

    -- Calculate weighted total (priority zones count more)
    local iWeightedTotal = (iPriorityZoneCount * iPriorityZoneScoutWeight) +
                           iLowIntelLandZones + iLowIntelWaterZones

    if bDebugMessages == true then
        LOG(sFunctionRef..': Team '..iTeam..' zones needing scouting: Priority='..iPriorityZoneCount..
            ', LowIntelLand='..iLowIntelLandZones..', LowIntelWater='..iLowIntelWaterZones..
            ', WeightedTotal='..iWeightedTotal)
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
    return iWeightedTotal, iPriorityZoneCount, iLowIntelLandZones, iLowIntelWaterZones
end

---Calculate the desired number of air scouts based on zones needing scouting
---Scales dynamically: more zones needing scouting = more scouts desired
---@param iTeam number Team index
---@param iGameEnderCount number Number of game enders (nukes, etc) that need extra scouting
---@return number Desired number of air scouts
function GetDesiredAirScoutCount(iTeam, iGameEnderCount)
    local sFunctionRef = 'GetDesiredAirScoutCount'
    local bDebugMessages, tDebugContext = M28Profiler.GetDebugControl(M28Profiler.refDebugChannelIntel, sFunctionRef)
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iWeightedZones = GetZonesNeedingScoutingCount(iTeam)

    -- Base calculation: minimum scouts + zones/ratio
    local iDesiredScouts = iMinAirScouts + math.ceil(iWeightedZones / iZonesPerScout)

    -- Add extra scouts for game enders (nukes need target scouting)
    local iGameEnderBonus = (iGameEnderCount or 0)
    iDesiredScouts = iDesiredScouts + iGameEnderBonus

    -- Clamp to min/max range
    iDesiredScouts = math.max(iMinAirScouts, math.min(iMaxAirScouts, iDesiredScouts))

    if bDebugMessages == true then
        LOG(sFunctionRef..': Team '..iTeam..' desired air scouts='..iDesiredScouts..
            ' (zones='..iWeightedZones..', gameEnders='..(iGameEnderCount or 0)..')')
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
    return iDesiredScouts
end

--===========================================
-- DEBUG AND VISUALIZATION
--===========================================

---Get a summary of intel confidence across all zones for debugging
---@param iTeam number Team index
---@return string Summary string for logging
function GetIntelConfidenceSummary(iTeam)
    local sFunctionRef = 'GetIntelConfidenceSummary'
    local sOutput = 'Intel Confidence Summary for Team '..iTeam..':\n'

    local iHighCount = 0
    local iMediumCount = 0
    local iLowCount = 0
    local iTotalZones = 0

    -- Land zones
    for iPlateau, tPlateauSubtable in M28Map.tAllPlateaus do
        if M28Utilities.IsTableEmpty(tPlateauSubtable[M28Map.subrefPlateauLandZones]) == false then
            for iLandZone, tLZData in tPlateauSubtable[M28Map.subrefPlateauLandZones] do
                local tLZTeamData = tLZData[M28Map.subrefLZTeamData][iTeam]
                if tLZTeamData then
                    iTotalZones = iTotalZones + 1
                    local iConfidence = GetZoneIntelConfidence(tLZTeamData, iTeam, 5)
                    local iLevel = GetIntelConfidenceLevel(iConfidence)

                    if iLevel == refiIntelHigh then
                        iHighCount = iHighCount + 1
                    elseif iLevel == refiIntelMedium then
                        iMediumCount = iMediumCount + 1
                    else
                        iLowCount = iLowCount + 1
                    end
                end
            end
        end
    end

    sOutput = sOutput..'Land Zones: '..iTotalZones..' total, HIGH='..iHighCount..', MEDIUM='..iMediumCount..', LOW='..iLowCount..'\n'

    -- Water zones
    iHighCount = 0
    iMediumCount = 0
    iLowCount = 0
    local iWaterZones = 0

    for iPond, tPondSubtable in M28Map.tPondDetails do
        if M28Utilities.IsTableEmpty(tPondSubtable[M28Map.subrefPondWaterZones]) == false then
            for iWaterZone, tWZData in tPondSubtable[M28Map.subrefPondWaterZones] do
                local tWZTeamData = tWZData[M28Map.subrefWZTeamData][iTeam]
                if tWZTeamData then
                    iWaterZones = iWaterZones + 1
                    local iConfidence = GetZoneIntelConfidence(tWZTeamData, iTeam, 5)
                    local iLevel = GetIntelConfidenceLevel(iConfidence)

                    if iLevel == refiIntelHigh then
                        iHighCount = iHighCount + 1
                    elseif iLevel == refiIntelMedium then
                        iMediumCount = iMediumCount + 1
                    else
                        iLowCount = iLowCount + 1
                    end
                end
            end
        end
    end

    sOutput = sOutput..'Water Zones: '..iWaterZones..' total, HIGH='..iHighCount..', MEDIUM='..iMediumCount..', LOW='..iLowCount..'\n'

    -- Priority scout requests
    local tRequests = M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones] or {}
    sOutput = sOutput..'Priority Scout Requests: '..table.getn(tRequests)..'\n'

    return sOutput
end

---Log intel confidence for a specific zone (for debugging)
---@param iPlateau number Plateau number (or pond for water)
---@param iZone number Zone number
---@param iTeam number Team index
---@param bIsWaterZone boolean True if water zone
function LogZoneIntelDetails(iPlateau, iZone, iTeam, bIsWaterZone)
    local sFunctionRef = 'LogZoneIntelDetails'

    local tZoneTeamData
    if bIsWaterZone then
        local tPondData = M28Map.tPondDetails[iPlateau]
        if tPondData and tPondData[M28Map.subrefPondWaterZones][iZone] then
            tZoneTeamData = tPondData[M28Map.subrefPondWaterZones][iZone][M28Map.subrefWZTeamData][iTeam]
        end
    else
        local tPlateauData = M28Map.tAllPlateaus[iPlateau]
        if tPlateauData and tPlateauData[M28Map.subrefPlateauLandZones][iZone] then
            tZoneTeamData = tPlateauData[M28Map.subrefPlateauLandZones][iZone][M28Map.subrefLZTeamData][iTeam]
        end
    end

    if tZoneTeamData then
        local iCurrentTime = GetGameTimeSeconds()
        local iTimeLastVisual = tZoneTeamData[M28Map.refiTimeLastHadVisual] or 0
        local iRadar = tZoneTeamData[M28Map.refiRadarCoverage] or 0
        local iOmni = tZoneTeamData[M28Map.refiOmniCoverage] or 0
        local iConfidence = GetZoneIntelConfidence(tZoneTeamData, iTeam, 1)
        local iLevel = GetIntelConfidenceLevel(iConfidence)
        local sLevel = (iLevel == refiIntelHigh and 'HIGH') or (iLevel == refiIntelMedium and 'MEDIUM') or 'LOW'

        LOG(sFunctionRef..': '..(bIsWaterZone and 'Pond' or 'P')..iPlateau..'Z'..iZone..
            ' | Confidence='..math.floor(iConfidence)..' ('..sLevel..')' ..
            ' | LastVisual='..(iCurrentTime - iTimeLastVisual)..'s ago' ..
            ' | Radar='..iRadar..'% | Omni='..iOmni..'%' ..
            ' | Surprise='..(HadRecentIntelSurprise(tZoneTeamData) and 'YES' or 'no'))
    else
        LOG(sFunctionRef..': Zone '..(bIsWaterZone and 'Pond' or 'P')..iPlateau..'Z'..iZone..' not found')
    end
end

---Log comprehensive intel state for all zones of a team (debugging)
---@param iTeam number Team index
function LogFullIntelState(iTeam)
    local sFunctionRef = 'LogFullIntelState'
    LOG('========================================')
    LOG(sFunctionRef..': Full Intel State Dump for Team '..iTeam..' at time '..GetGameTimeSeconds())
    LOG('========================================')

    -- Summary
    LOG(GetIntelConfidenceSummary(iTeam))

    -- Low intel zones detail
    LOG('--- LOW INTEL ZONES (needing attention) ---')
    local iLowIntelCount = 0

    for iPlateau, tPlateauSubtable in M28Map.tAllPlateaus do
        if M28Utilities.IsTableEmpty(tPlateauSubtable[M28Map.subrefPlateauLandZones]) == false then
            for iLandZone, tLZData in tPlateauSubtable[M28Map.subrefPlateauLandZones] do
                local tLZTeamData = tLZData[M28Map.subrefLZTeamData][iTeam]
                if tLZTeamData then
                    local iConfidence = GetZoneIntelConfidence(tLZTeamData, iTeam, 5)
                    if GetIntelConfidenceLevel(iConfidence) == refiIntelLow then
                        iLowIntelCount = iLowIntelCount + 1
                        LogZoneIntelDetails(iPlateau, iLandZone, iTeam, false)
                    end
                end
            end
        end
    end

    for iPond, tPondSubtable in M28Map.tPondDetails do
        if M28Utilities.IsTableEmpty(tPondSubtable[M28Map.subrefPondWaterZones]) == false then
            for iWaterZone, tWZData in tPondSubtable[M28Map.subrefPondWaterZones] do
                local tWZTeamData = tWZData[M28Map.subrefWZTeamData][iTeam]
                if tWZTeamData then
                    local iConfidence = GetZoneIntelConfidence(tWZTeamData, iTeam, 5)
                    if GetIntelConfidenceLevel(iConfidence) == refiIntelLow then
                        iLowIntelCount = iLowIntelCount + 1
                        LogZoneIntelDetails(iPond, iWaterZone, iTeam, true)
                    end
                end
            end
        end
    end

    if iLowIntelCount == 0 then
        LOG('  (No low intel zones found)')
    end

    -- Priority scout requests
    LOG('--- PRIORITY SCOUT REQUESTS ---')
    local tRequests = M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones] or {}
    if table.getn(tRequests) == 0 then
        LOG('  (No priority requests)')
    else
        for iReq, tRequest in tRequests do
            LOG('  Request #'..iReq..': P'..tRequest.iPlateau..'Z'..tRequest.iZone..
                ' | Urgency='..tRequest.iUrgency..
                ' | Age='..(GetGameTimeSeconds() - tRequest.iTimeRequested)..'s')
        end
    end

    LOG('========================================')
end

---Enable/disable verbose intel logging globally
---@param bEnable boolean True to enable verbose logging
function SetVerboseIntelLogging(bEnable)
    -- This is a marker function - the actual logging is controlled by the M28Config debug channels.
    if bEnable then
        LOG('M28Intel: Enable verbose intel logging via M28Config.M28DebugIntel = true')
    end
end
