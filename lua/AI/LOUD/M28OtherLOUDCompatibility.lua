---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 29/06/2024 00:06
---

--Update unit categories

--1 issue - LOUD has removed ANTINAVY category, use destroyer and submarine as basic proxy
local M28UnitInfo = import('/mods/M28AI/lua/AI/M28UnitInfo.lua')
local M28Profiler = import('/mods/M28AI/lua/AI/M28Profiler.lua')
bUpdatedRepr = false
bUpdatedOtherLOUDInfo = false
bUpdatedUnitCategories = false

function AddReprCommands()
    if not(bUpdatedRepr) then
        bUpdatedRepr = true
        local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')
        _G.repru = rawget(_G, 'repru') or repr --With thanks to Balthazar for suggesting this for where e.g. FAF develop has a function that isnt yet in FAF main
        _G.reprs = rawget(_G, 'reprs') or
                function(tTable)
                    if tTable == nil then
                        return 'nil'
                    else
                        function GetVariableTypeOrValue(variable, iCurSubtableLevel)
                            if type(variable) == 'nil' then
                                return 'nil'
                            elseif type(variable) == 'number' then
                                return variable
                            elseif type(variable) == 'string' then
                                return variable
                            elseif type(variable) == 'boolean' then
                                if variable then return 'True' else return 'False' end
                            elseif type(variable) == 'function' then
                                return '<function>'
                            elseif type(variable) == 'userdata' then
                                return '<userdata>'
                            elseif type(variable) == 'thread' then
                                return '<thread>'
                            elseif type(variable) == 'table' then
                                local sCombinedTable = ''
                                for iEntry, vValue in variable do
                                    if iCurSubtableLevel and iCurSubtableLevel >= 1 then
                                        sCombinedTable = sCombinedTable..'['..iEntry..']='..'Value (stopped for performance)'
                                    else
                                        sCombinedTable = sCombinedTable..'['..iEntry..']='..GetVariableTypeOrValue(vValue, (iCurSubtableLevel or 0) + 1)
                                    end
                                end
                                return sCombinedTable
                            else
                                return '<unexpected type>'
                            end
                        end

                        return GetVariableTypeOrValue(tTable)

                    end --With thanks to Balthazar for suggesting this for where e.g. FAF develop has a function that isnt yet in FAF main
                end
        if M28Utilities.bLoudModActive or M28Utilities.bSteamActive then
            _G.repr = function(tTable)
                if tTable == nil then
                    return 'nil'
                else
                    function GetVariableTypeOrValue(variable, iCurSubtableLevel)
                        if type(variable) == 'nil' then
                            return 'nil'
                        elseif type(variable) == 'number' then
                            return variable
                        elseif type(variable) == 'string' then
                            return variable
                        elseif type(variable) == 'boolean' then
                            if variable then return 'True' else return 'False' end
                        elseif type(variable) == 'function' then
                            return '<function>'
                        elseif type(variable) == 'userdata' then
                            return '<userdata>'
                        elseif type(variable) == 'thread' then
                            return '<thread>'
                        elseif type(variable) == 'table' then
                            local sCombinedTable = ''
                            for iEntry, vValue in variable do
                                if iCurSubtableLevel and iCurSubtableLevel >= 3 then
                                    sCombinedTable = sCombinedTable..'['..iEntry..']='..'Value (stopped for performance)'
                                else
                                    sCombinedTable = sCombinedTable..'['..iEntry..']='..GetVariableTypeOrValue(vValue, (iCurSubtableLevel or 0) + 1)
                                end
                            end
                            return sCombinedTable
                        else
                            return '<unexpected type>'
                        end
                    end

                    return GetVariableTypeOrValue(tTable, 0)
                end
            end
        end
    end
end

function UpdateOtherLOUDInformation()
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    local sFunctionRef = 'UpdateOtherLOUDInformation'
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)
    if not(bUpdatedOtherLOUDInfo) then
        bUpdatedOtherLOUDInfo = true
        AddReprCommands()

        local M28Building = import('/mods/M28AI/lua/AI/M28Building.lua')
        M28Building.bShieldsCanDischarge = false

        --fix the scenarioinfo values from custom game options if are in LOUD, as it uses keys
        local LobbyOptions = import('/mods/M28AI/lua/CustomOptions/M28LOUDLobbyOptions.lua')
        local vCurKey
        if bDebugMessages == true then LOG(sFunctionRef..': About to go through lobby options and update scenario info, LobbyOptions.LobbyGlobalOptions='..repru(LobbyOptions.LobbyGlobalOptions)) end
        local bUseKeyForValue
        for iEntry, tOptionData in LobbyOptions.LobbyGlobalOptions do
            vCurKey = ScenarioInfo.Options[tOptionData.key]
            bUseKeyForValue = tOptionData.bUseKeyAsValueInScenarioInfo or false
            if bDebugMessages == true then LOG(sFunctionRef..': Considering vCurKey='..(vCurKey or 'nil')..'; tOptionData.key='..(tOptionData.key or 'nil')..'; iEntry='..iEntry) end
            for iValueEntry, tValueData in tOptionData.values do
                if bDebugMessages == true then LOG(sFunctionRef..': Considering tValueData.key='..tValueData.key or 'nil') end
                if tValueData.key == vCurKey then
                    if bDebugMessages == true then LOG(sFunctionRef..': Replacing scenario info for option Data key='..tOptionData.key..'; Scenario info value='..ScenarioInfo.Options[tOptionData.key]..'; Will change to tValueData.text='..tValueData.text..'; bUseKeyForValue='..tostring(bUseKeyForValue)..'; tValueData.key='..(tValueData.key or 'nil')) end
                    if bUseKeyForValue then
                        ScenarioInfo.Options[tOptionData.key] = tValueData.key
                    else
                        ScenarioInfo.Options[tOptionData.key] = tValueData.text
                    end
                    break
                end
            end
        end
        if bDebugMessages == true then LOG(sFunctionRef..': M28CombinedArmy='..(ScenarioInfo.Options.M28CombinedArmy or 'nil')) end
    end

    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

function UpdateUnitCategories()
    if not(bUpdatedUnitCategories) then
        bUpdatedUnitCategories = true
        --Land based:
        --lack of BOT category for experimentals
        M28UnitInfo.refCategoryMonkeylord = categories.CYBRAN * categories.MOBILE * categories.EXPERIMENTAL * categories.DIRECTFIRE - categories.CONSTRUCTION + categories.url0402
        M28UnitInfo.refCategoryMegalith = categories.CYBRAN * categories.MOBILE * categories.EXPERIMENTAL * categories.DIRECTFIRE * categories.CONSTRUCTION + categories.xrl0403
        M28UnitInfo.refCategoryYthotha = M28UnitInfo.refCategoryYthotha + categories.xsl0401
        M28UnitInfo.refCategoryFatboy = M28UnitInfo.refCategoryFatboy + categories.uel0401
        --lack of PERSONALSHIELD category:
        M28UnitInfo.refCategoryObsidian = M28UnitInfo.refCategoryObsidian + categories.ual0202
        M28UnitInfo.refCategoryPersonalShield = M28UnitInfo.refCategoryPersonalShield + categories.uel0303 + categories.ual0303
        --STEALTHFIELD
        M28UnitInfo.refCategoryMobileLandStealth = M28UnitInfo.refCategoryMobileLandStealth + categories.CYBRAN * categories.COUNTERINTELLIGENCE * categories.MOBILE * categories.LAND + categories.url0306
        M28UnitInfo.refCategoryStealthBoat = M28UnitInfo.refCategoryStealthBoat + categories.CYBRAN * categories.OVERLAYCOUNTERINTEL * categories.NAVAL * categories.DEFENSIVEBOAT + categories.xrs0205
        M28UnitInfo.refCategoryStealthGenerator = M28UnitInfo.refCategoryStealthGenerator + categories.COUNTERINTELLIGENCE * categories.STRUCTURE * categories.TECH2 + categories.ueb4203 + categories.urb4203 + categories.uab4203 + categories.xsb4203
        --STEALTH
        M28UnitInfo.refCategoryStealthAndCloakPersonal = M28UnitInfo.refCategoryStealthAndCloakPersonal + categories.xsl0101
        --BOMB
        M28UnitInfo.refCategoryMobileBomb = M28UnitInfo.refCategoryMobileBomb + categories.xrl0302
        M28UnitInfo.refCategoryMercy = M28UnitInfo.refCategoryMercy + categories.daa0206

        --Naval based:
        M28UnitInfo.refCategoryAntiNavy = M28UnitInfo.refCategoryAntiNavy + categories.DESTROYER + categories.SUBMARINE
        M28UnitInfo.refCategorySubmarine = M28UnitInfo.refCategorySubmarine + categories.SUBMARINE
        M28UnitInfo.refCategoryGroundAA = M28UnitInfo.refCategoryGroundAA + categories.NAVALCARRIER
        M28UnitInfo.refCategoryBattlecruiser = M28UnitInfo.refCategoryBattlecruiser + categories.CRUISER * categories.UEF * categories.TECH3 * categories.DIRECTFIRE + categories.xes0307
        M28UnitInfo.refCategoryMissileShip = M28UnitInfo.refCategoryMissileShip + categories.NAVAL * categories.MOBILE * categories.INDIRECTFIRE * categories.BOMBARDMENT - categories.SUBMERSIBLE
        M28UnitInfo.refCategoryNavalAA = M28UnitInfo.refCategoryNavalAA + M28UnitInfo.refCategoryAntiAir * categories.NAVAL * categories.MOBILE + categories.CRUISER * categories.MOBILE * categories.TECH2 + categories.NAVALCARRIER * categories.MOBILE * categories.TECH3 + categories.NAVALCARRIER * categories.EXPERIMENTAL * categories.MOBILE
        M28UnitInfo.refCategoryNavalSurface = M28UnitInfo.refCategoryNavalSurface + categories.DESTROYER + categories.CRUISER + categories.BATTLESHIP --destroyer is necessary, other 2 are as redundancy
    end
end