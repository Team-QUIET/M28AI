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
function CalculateIntelConfidence(tLZOrWZTeamData, iTeam)
    local sFunctionRef = 'CalculateIntelConfidence'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    local iCurrentTime = GetGameTimeSeconds()
    
    -- Get time since last visual
    local iTimeLastVisual = tLZOrWZTeamData[M28Map.refiTimeLastHadVisual] or 0
    local iTimeSinceVisual = iCurrentTime - iTimeLastVisual
    local iVisualScore = GetVisualConfidenceScore(iTimeSinceVisual)
    
    -- Get radar and omni coverage (already 0-100 scale)
    local iRadarScore = tLZOrWZTeamData[M28Map.refiRadarCoverage] or 0
    local iOmniScore = tLZOrWZTeamData[M28Map.refiOmniCoverage] or 0
    
    -- Calculate weighted confidence
    local iConfidence = (iVisualScore * iVisualWeight) + 
                        (iRadarScore * iRadarWeight) + 
                        (iOmniScore * iOmniWeight)
    
    -- Clamp to 0-100 range
    iConfidence = math.max(0, math.min(100, iConfidence))
    
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
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then bDebugMessages = true end
    local sFunctionRef = 'RefreshAllLandZoneIntelConfidence'
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
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then bDebugMessages = true end
    local sFunctionRef = 'GetZonesNeedingArmyScouting'
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
function RequestPriorityScoutingForZone(iPlateau, iLandOrWaterZone, iTeam, iUrgency)
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then bDebugMessages = true end
    local sFunctionRef = 'RequestPriorityScoutingForZone'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)

    -- Store in team data for air scouts to pick up
    if not(M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones]) then
        M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones] = {}
    end

    local tZoneRequest = {
        iPlateau = iPlateau,
        iZone = iLandOrWaterZone,
        iUrgency = iUrgency or 50,
        iTimeRequested = GetGameTimeSeconds()
    }

    -- Check if already in list
    local bAlreadyRequested = false
    for iEntry, tExisting in M28Team.tTeamData[iTeam][M28Team.reftPriorityScoutZones] do
        if tExisting.iPlateau == iPlateau and tExisting.iZone == iLandOrWaterZone then
            -- Update urgency if higher
            if iUrgency > tExisting.iUrgency then
                tExisting.iUrgency = iUrgency
                tExisting.iTimeRequested = GetGameTimeSeconds()
            end
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
        if iCurrentTime - tRequest.iTimeRequested < 30 then
            table.insert(tValidRequests, tRequest)
        end
    end

    -- Sort by urgency
    table.sort(tValidRequests, function(a, b) return a.iUrgency > b.iUrgency end)

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
    local iTimeLastVisual = tLZOrWZTeamData[M28Map.refiTimeLastHadVisual] or 0
    local iTimeSinceVisual = iCurrentTime - iTimeLastVisual

    -- Get mobility-adjusted visual score
    local iVisualScore = GetMobilityAdjustedVisualConfidence(iTimeSinceVisual, iThreatType)

    -- Radar and omni remain the same
    local iRadarScore = tLZOrWZTeamData[M28Map.refiRadarCoverage] or 0
    local iOmniScore = tLZOrWZTeamData[M28Map.refiOmniCoverage] or 0

    local iConfidence = (iVisualScore * iVisualWeight) +
                        (iRadarScore * iRadarWeight) +
                        (iOmniScore * iOmniWeight)

    return math.max(0, math.min(100, iConfidence))
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
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then bDebugMessages = true end
    local sFunctionRef = 'DetectIntelSurprise'

    local iCurrentTime = GetGameTimeSeconds()
    local iConfidence = GetZoneIntelConfidence(tLZOrWZTeamData, iTeam, 2)

    -- Calculate threat difference
    local iThreatDifference = iActualThreat - (iPreviousKnownThreat or 0)

    -- Surprise if significant new threat appears and we thought we had good intel
    if iThreatDifference >= iSurpriseThreatThreshold and iConfidence >= iSurpriseConfidenceThreshold then
        tLZOrWZTeamData[refbIntelSurpriseDetected] = true
        tLZOrWZTeamData[refiSurpriseThreatAmount] = iThreatDifference

        if bDebugMessages == true then
            LOG(sFunctionRef..': INTEL SURPRISE! Expected threat='..(iPreviousKnownThreat or 0)..
                ' but found='..iActualThreat..' (diff='..iThreatDifference..
                ') despite confidence='..iConfidence)
        end
        return true
    end

    -- Clear surprise flag if not currently surprised
    tLZOrWZTeamData[refbIntelSurpriseDetected] = false
    tLZOrWZTeamData[refiSurpriseThreatAmount] = 0
    return false
end

---Check if zone recently had an intel surprise
---@param tLZOrWZTeamData table Zone team data
---@return boolean True if zone had recent intel surprise
function HadRecentIntelSurprise(tLZOrWZTeamData)
    return tLZOrWZTeamData[refbIntelSurpriseDetected] == true
end

---Get the amount of surprise threat that appeared
---@param tLZOrWZTeamData table Zone team data
---@return number Amount of unexpected threat
function GetSurpriseThreatAmount(tLZOrWZTeamData)
    return tLZOrWZTeamData[refiSurpriseThreatAmount] or 0
end

--===========================================
-- NAVAL ZONE INTEL FUNCTIONS
--===========================================

---Get water zones needing urgent scouting near friendly naval forces
---@param iTeam number Team index
---@param iMaxZones number Maximum number of zones to return
---@return table Array of {iPond, iWaterZone, iUrgency} for zones needing scouts
function GetWaterZonesNeedingNavyScouting(iTeam, iMaxZones)
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then bDebugMessages = true end
    local sFunctionRef = 'GetWaterZonesNeedingNavyScouting'
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
    -- This is a marker function - the actual logging is controlled by M28Profiler.bGlobalDebugOverride
    if bEnable then
        LOG('M28Intel: Verbose logging can be enabled via M28Profiler.bGlobalDebugOverride = true')
    end
end