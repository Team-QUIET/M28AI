
local M28Map = import('/mods/M28AI/lua/AI/M28Map.lua')

--Approach of hooking to get around adaptive map issues is based on Softels DilliDalli AI - alternative is using CanBuildStructureAt to check, but that runs into issues if the resource point has reclaim on it
local M28OldCreateResourceDeposit = CreateResourceDeposit
local M28Events = import('/mods/M28AI/lua/AI/M28Events.lua')

CreateResourceDeposit = function(t,x,y,z,size)
    M28OldCreateResourceDeposit(t,x,y,z,size)
    ForkThread(M28Map.RecordResourcePoint,t,x,y,z,size)
end

--Put anything we want to only run once (not once per aiBrain) below
local M28BeginSession = BeginSession
function BeginSession()
    M28BeginSession()
    ForkThread(M28Events.OnGameStart)
end