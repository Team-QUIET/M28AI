---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 02/12/2022 08:29
---
local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')
local M28UnitInfo = import('/mods/M28AI/lua/AI/M28UnitInfo.lua')

function ManageACU(aiBrain)
    --First get our ACU
    local oACU
    while not(oACU) do
        local tOurACU = aiBrain:GetListOfUnits(categories.COMMAND, false, true)
        if M28Utilities.IsTableEmpty(tOurACU) == false then
            for _, oUnit in tOurACU do
                oACU = oUnit
                break
            end
        end
        if oACU then break end

        WaitTicks(1)
    end


    while M28UnitInfo.IsUnitValid(oACU) do
        --Early game - do we want to build factory/power?
        WaitSeconds(1)
    end
end