---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 02/10/2024 19:28
---
--[[function TrackProj(projectitem, self)
    --LOUD has code that applies only to M28 and can cause wierd results like shells that fly through the air when targeting M28's units instead of hitting them; therefore disabled
    --(if the TrackProj code was put in due to a dislike of M28 units trying to dodge t1 arti/MML fire, it is noted that a game option (key M28DodgeMicro) is available for users to enable/disable such logic already via the game lobby options, with no need for providing auto-homing shots to all units against M28)
    --v131 - commented out on the understanding the bug was caused by debug code left in (and a destructive hook isnt desirable long term to fix the bug caused by this logic due to the risk in the future such a function might be used for LOUD gameplay features)
end--]]