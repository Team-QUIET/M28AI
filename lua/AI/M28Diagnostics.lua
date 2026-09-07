-- Focused decision traces. This module must never issue orders, use random numbers,
-- inspect units, or write to brain/unit/zone state. Call ShouldLog BEFORE building fields.
local Config = import('/mods/M28AI/lua/M28Config.lua')
local tLast = {}
local tRing = {}
local iNext = 1
local iSize = 0
local iSecond = -1
local iLines = 0
local tChannelLines = {}
local iSuppressed = 0
local iLastSummary = -10
local tLosses = {}

function Enabled(sChannel, iArmy)
    -- Imported modules fall through to strict _G in FA. Optional/nil settings
    -- must use rawget; a normal missing-field lookup raises instead of returning nil.
    if rawget(Config, 'M28ReplayDiagnostics') ~= true then return false end
    local tChannels = rawget(Config, 'M28ReplayDiagnosticChannels')
    local iArmyFilter = rawget(Config, 'M28ReplayDiagnosticArmy')
    return (not(tChannels) or tChannels[sChannel] == true)
        and (not(iArmy) or not(iArmyFilter) or iArmyFilter == iArmy)
end

function ShouldLog(sChannel, iArmy, sIdentity)
    if not(Enabled(sChannel, iArmy)) then return false end
    local iNow = GetGameTimeSeconds()
    local iNowSecond = math.floor(iNow)
    if iSecond ~= iNowSecond then
        iSecond = iNowSecond
        iLines = 0
        tChannelLines = {}
    end
    local sKey = sChannel..':'..tostring(iArmy or 0)..':'..tostring(sIdentity)
    if iNow - (tLast[sKey] or -100000) < math.max(1, rawget(Config, 'M28ReplayDiagnosticInterval') or 10) then return false end
    if iLines >= math.max(1, rawget(Config, 'M28ReplayDiagnosticLinesPerSecond') or 24)
        or (tChannelLines[sChannel] or 0) >= math.max(1, rawget(Config, 'M28ReplayDiagnosticChannelLinesPerSecond') or 6) then
        iSuppressed = iSuppressed + 1
        return false
    end
    if not(tLast[sKey]) then
        -- Fixed-size FIFO: no scans and no references to game objects retained.
        local iLimit = 1024
        if tRing[iNext] then tLast[tRing[iNext]] = nil else iSize = iSize + 1 end
        tRing[iNext] = sKey
        iNext = iNext + 1
        if iNext > iLimit then iNext = 1 end --FA's LuaPlus parser has no % operator.
    end
    tLast[sKey] = iNow
    iLines = iLines + 1
    tChannelLines[sChannel] = (tChannelLines[sChannel] or 0) + 1
    return true
end

local function Clean(vValue)
    return string.sub((string.gsub(tostring(vValue), '[\r\n|]', ' ')), 1, 120)
end

function Record(sChannel, iArmy, sIdentity, sReason, tFields)
    -- Only call after admission. Flat primitive fields keep formatting bounded.
    local iNow = GetGameTimeSeconds()
    local tParts = {'M28DIAG', 't='..string.format('%.1f', iNow), 'channel='..Clean(sChannel),
        'army='..Clean(iArmy or 0), 'key='..Clean(sIdentity), 'reason='..Clean(sReason)}
    local tKeys = {}
    for sKey, _ in pairs(tFields or {}) do table.insert(tKeys, sKey) end
    table.sort(tKeys)
    for i, sKey in ipairs(tKeys) do
        if i > 20 then break end
        table.insert(tParts, Clean(sKey)..'='..Clean(tFields[sKey]))
    end
    if iNow - iLastSummary >= 10 then
        table.insert(tParts, 'budget_suppressed='..iSuppressed)
        table.insert(tParts, 'retained_keys='..iSize)
        iSuppressed = 0
        iLastSummary = iNow
    end
    LOG(table.concat(tParts, '|'))
end

function CountLandLoss(iArmy, iMass, bT3PD, bUnknownKiller)
    if not(Enabled('Events', iArmy)) then return end
    local tLoss = tLosses[iArmy]
    if not(tLoss) then
        tLoss = {units = 0, mass = 0, t3_pd_units = 0, t3_pd_mass = 0, unknown_killer_units = 0}
        tLosses[iArmy] = tLoss
    end
    tLoss.units = tLoss.units + 1
    tLoss.mass = tLoss.mass + (iMass or 0)
    if bT3PD then
        tLoss.t3_pd_units = tLoss.t3_pd_units + 1
        tLoss.t3_pd_mass = tLoss.t3_pd_mass + (iMass or 0)
    elseif bUnknownKiller then tLoss.unknown_killer_units = tLoss.unknown_killer_units + 1 end
end

function FlushLosses()
    if not(Enabled('Events')) then return end
    for iArmy, tLoss in pairs(tLosses) do
        if ShouldLog('Events', iArmy, 'land-losses') then Record('Events', iArmy, 'land-losses', 'cumulative-observed-losses', tLoss) end
    end
end
