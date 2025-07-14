# M28 Air Production and Early Air Contest Analysis

## Current Issues Identified

### 1. Early Air Factory Production Problems
Based on code analysis in `DoWeWantAirFactoryInsteadOfLandFactory` (lines 1948-2200+ in M28Conditions.lua), M28 has several issues with early air production:

- **Delayed Air Factory Building**: The logic heavily favors land factories in early game, especially when on same island as enemy
- **Energy Dependency**: Air factory production is heavily gated by energy requirements, causing delays
- **Conservative Approach**: Multiple conditions must be met before prioritizing air over land factories

### 2. T1 Bomber Production Gaps
From the analysis, several factors contribute to weak early bomber production:

- **Factory Upgrade Priority**: M28 tends to upgrade factories rather than mass-produce T1 bombers
- **Resource Allocation**: Mass and energy are often directed to land units first
- **Timing Issues**: Air factories are built too late to contest early T1 bomber rushes

### 3. Air vs Land Factory Decision Logic Issues
Current decision-making in `DoWeWantAirFactoryInsteadOfLandFactory`:

- Over-prioritizes land when enemy is on same island (lines ~2052-2080)
- Energy stalling heavily penalizes air factory construction
- Conservative thresholds for air factory count relative to land factories

## Specific Code Areas Needing Improvement

### 1. Early Game Air Priority (Lines 1975-1985)
```lua
-- Current: Only goes second air if very specific conditions met
if aiBrain[M28Economy.refiOurHighestAirFactoryTech] == 0 and aiBrain[M28Economy.refbGoingSecondAir] 
   and aiBrain:GetEconomyStored('MASS') <= 40 and aiBrain[M28Economy.refiNetMassBaseIncome] < 0
```

**Problem**: Too restrictive - requires negative mass income and low stored mass

### 2. Island-Based Logic (Lines 2052-2070)
```lua
-- Current: Heavily favors land when on same island as enemy
if (M28Team.tTeamData[iTeam][M28Team.subrefiHighestFriendlyAirFactoryTech] > 0 or M28Map.iMapSize < 512) 
   and (conditions_that_favor_land_heavily)
```

**Problem**: Doesn't account for early air superiority benefits even on same island

### 3. Energy Gating (Lines 2050-2055)
```lua
-- Current: Heavy penalty for energy issues
if M28Team.tTeamData[iTeam][M28Team.subrefiTeamAverageEnergyPercentStored] <= 0.9 
   or M28Team.tTeamData[iTeam][M28Team.subrefiTeamGrossEnergy] <= (previous_energy_threshold)
```

**Problem**: Energy constraints prevent early air even when strategically beneficial

## Recommendations

### 1. Early Air Production Improvements

#### A. Modify Early Game Air Priority
- **Location**: Lines 1975-1985 in `DoWeWantAirFactoryInsteadOfLandFactory`
- **Change**: Reduce restrictions for going second air
- **New Logic**: Allow air factory if enemy has shown early air or map size > 256

#### B. Add Early Bomber Detection
- **Location**: Add new condition in `DoWeWantAirFactoryInsteadOfLandFactory`
- **Logic**: If enemy has built T1 bombers, prioritize air factory immediately
- **Implementation**: Check enemy bomber count in team data

#### C. Reduce Energy Gating for Early Air
- **Location**: Lines 2050-2055
- **Change**: Allow air factories even with moderate energy issues if strategic benefit exists
- **Condition**: If GameTime < 300 and enemy air threat detected

### 2. T1 Bomber Mass Production

#### A. Factory Upgrade Delays
- **Location**: Factory upgrade logic in M28Factory.lua
- **Change**: Delay T2 air factory upgrades if T1 bomber production needed
- **Trigger**: Enemy land units detected and insufficient T1 bomber count

#### B. Bomber Build Priority
- **Location**: Air factory production queues
- **Change**: Prioritize T1 bombers over scouts when land threat exists
- **Threshold**: Build 4-6 T1 bombers before other units

### 3. Air Contest Strategy

#### A. Early Air Superiority Detection
- **Implementation**: Add function to detect when air superiority is beneficial
- **Factors**: Map size, enemy air units, land unit vulnerability
- **Usage**: Override normal land/air factory ratios when air superiority critical

#### B. Bomber Rush Counter
- **Location**: Enemy threat assessment
- **Logic**: If enemy has early bombers, immediately prioritize air defense and counter-air
- **Response**: Build interceptors and additional air factories

### 4. Specific Code Changes Needed

#### A. Modify `DoWeWantAirFactoryInsteadOfLandFactory` (M28Conditions.lua)
```lua
-- Add early bomber threat detection
if GetGameTimeSeconds() <= 180 then
    local iEnemyBomberCount = GetEnemyUnitCount(categories.BOMBER * categories.TECH1, iTeam)
    if iEnemyBomberCount >= 2 and aiBrain[M28Economy.refiOurHighestAirFactoryTech] == 0 then
        return true -- Emergency air factory needed
    end
end

-- Reduce energy gating for early air
if GetGameTimeSeconds() <= 240 and M28Map.iMapSize >= 512 then
    -- Allow air factory even with energy constraints if strategic benefit
    if iLandFactoriesHave >= 1 and not(bHaveAirFactory) and (enemy_air_threat_detected) then
        return true
    end
end
```

#### B. Factory Production Priority (M28Factory.lua)
- Modify build queues to prioritize T1 bombers when enemy land economy vulnerable
- Add logic to detect enemy economy exposure to bomber raids
- Implement mass T1 bomber production mode

#### C. Early Game Air Strategy
- Add function `ShouldRushEarlyAir()` to detect beneficial air rush scenarios
- Integrate with existing factory decision logic
- Override conservative approaches when air superiority crucial

### 5. Testing Priorities

1. **5km+ Maps**: Test early air factory timing and bomber production
2. **Enemy Bomber Defense**: Verify rapid response to enemy T1 bomber threats  
3. **Resource Balancing**: Ensure changes don't break economy management
4. **Air Superiority**: Test sustained air production for map control

### 6. Integration Points

The changes should integrate with existing systems:
- **M28Team**: Enemy unit tracking for bomber detection
- **M28Economy**: Resource management for air factory decisions
- **M28Factory**: Production queue modifications
- **M28Overseer**: Strategic decision making

## Implementation Priority

1. **High Priority**: Early bomber threat detection and response
2. **Medium Priority**: Reduced energy gating for strategic air
3. **Low Priority**: Advanced air superiority calculations

These changes should significantly improve M28's ability to contest early air and respond to T1 bomber threats while maintaining the overall strategic balance of the AI.