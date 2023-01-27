---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 30/11/2022 22:36
---

--LOCAL FILE DECLARATIONS - Do after the below global ones as for m28engineer it refers to some of these global variables

--Order info
reftiLastOrders = 'M28OrdersLastOrders' --Against unit, table first of the order number (1 = first order given, 2 = 2nd etc., qhere they were queued), which returns a table containing all the details of the order (including the order type per the below reference integers)
refiOrderCount = 'M28OrdersCount' --Size of the table of last orders

--Subtables for each order:
subrefiOrderType = 1
subreftOrderPosition = 2
subrefoOrderTarget = 3
subrefsOrderBlueprint = 4

--Order type references
refiOrderIssueMove = 1
refiOrderIssueFormMove = 2
refiOrderIssueAttack = 3
refiOrderIssueAggressiveMove = 4
refiOrderIssueAggressiveFormMove = 5
refiOrderIssueReclaim = 6
refiOrderIssueGuard = 7
refiOrderIssueRepair = 8
refiOrderIssueBuild = 9
refiOrderOvercharge = 10
refiOrderUpgrade = 11 --For building upgrades; ACU upgrades are refiOrderEnhancement
refiOrderTransportLoad = 12
refiOrderIssueGroundAttack = 13
refiOrderIssueFactoryBuild = 14
refiOrderKill = 15 --If we want to self destruct a unit
refiOrderEnhancement = 16 --I.e. ACU upgrades

--Other tracking: Against units
toUnitsOrderedToRepairThis = 'M28OrderRepairing' --Table of units given an order to repair the unit
refiEstimatedLastPathPoint = 'M28OrderLastPathRef' --If a unit is being given an order to follow a path, then when its orders are refreshed this shoudl be updated based on what path we think is currently the target

local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')
local M28UnitInfo = import('/mods/M28AI/lua/AI/M28UnitInfo.lua')
local M28Engineer = import('/mods/M28AI/lua/AI/M28Engineer.lua')
local M28Config = import('/mods/M28AI/lua/M28Config.lua')
local M28Map = import('/mods/M28AI/lua/AI/M28Map.lua')
local M28Profiler = import('/mods/M28AI/lua/AI/M28Profiler.lua')
local M28Team = import('/mods/M28AI/lua/AI/M28Team.lua')


function UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc)
    local sBaseOrder = 'Clear'
    if oUnit[reftiLastOrders] then
        sBaseOrder = (oUnit[reftiLastOrders][oUnit[refiOrderCount]][subrefiOrderType] or 'Unknown')
    end
    local sExtraOrder = ''
    if sOptionalOrderDesc then sExtraOrder = ' '..sOptionalOrderDesc end
    local sPlateauAndZoneDesc = ''
    if EntityCategoryContains(categories.LAND + categories.NAVAL, oUnit.UnitId) then
        local iPlateau, iLandZone = M28Map.GetPlateauAndLandZoneReferenceFromPosition(oUnit:GetPosition(), false)
        sPlateauAndZoneDesc = ':P='..(iPlateau or 0)..'LZ='..(iLandZone or 0)
    end
    oUnit:SetCustomName(oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit)..sPlateauAndZoneDesc..':'..sBaseOrder..sExtraOrder)
end

function IssueTrackedClearCommands(oUnit)
    --Update tracking for repairing units:
    if oUnit[reftiLastOrders] then
        local tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        if tLastOrder[subrefiOrderType] == refiOrderIssueRepair then
            if M28UnitInfo.IsUnitValid(tLastOrder[subrefoOrderTarget]) and M28Utilities.IsTableEmpty(tLastOrder[subrefoOrderTarget][toUnitsOrderedToRepairThis]) == false then
                local iRefToRemove
                for iRepairer, oRepairer in tLastOrder[subrefoOrderTarget][toUnitsOrderedToRepairThis] do
                    if oRepairer == oUnit then
                        iRefToRemove = iRepairer
                        break
                    end
                end
                if iRefToRemove then table.remove(tLastOrder[subrefoOrderTarget][toUnitsOrderedToRepairThis], iRefToRemove) end
            end
        elseif tLastOrder[subrefiOrderType] == refiOrderIssueGuard then
            if M28UnitInfo.IsUnitValid(tLastOrder[subrefoOrderTarget]) and M28Utilities.IsTableEmpty(tLastOrder[subrefoOrderTarget][M28UnitInfo.reftoUnitsAssistingThis]) == false then
                local iRefToRemove
                for iAssister, oAssister in tLastOrder[subrefoOrderTarget][M28UnitInfo.reftoUnitsAssistingThis] do
                    if oAssister == oUnit then
                        iRefToRemove = iAssister
                        break
                    end
                end
                if iRefToRemove then table.remove(tLastOrder[subrefoOrderTarget][M28UnitInfo.reftoUnitsAssistingThis], iRefToRemove) end
            end
        end
    end
    oUnit[reftiLastOrders] = nil
    oUnit[refiOrderCount] = 0

    if oUnit[M28Engineer.reftUnitsWeAreReclaiming] and M28Utilities.IsTableEmpty(oUnit[M28Engineer.reftUnitsWeAreReclaiming]) == false then
        for iUnitBeingReclaimed, oUnitBeingReclaimed in oUnit[M28Engineer.reftUnitsWeAreReclaiming] do
            if oUnitBeingReclaimed.UnitId and M28Utilities.IsTableEmpty(oUnitBeingReclaimed[M28Engineer.reftUnitsReclaimingUs]) == false then
                for iReclaimer, oReclaimer in oUnitBeingReclaimed[M28Engineer.reftUnitsReclaimingUs] do
                    if oReclaimer == oUnit then
                        table.remove(oUnitBeingReclaimed[M28Engineer.reftUnitsReclaimingUs], iReclaimer)
                        break
                    end
                end
            end
        end
        oUnit[M28Engineer.reftUnitsWeAreReclaiming] = nil
    end

    --Update tracking for engineers:
    if EntityCategoryContains(M28UnitInfo.refCategoryEngineer + categories.COMMAND + categories.SUBCOMMANDER, oUnit.UnitId) then
        M28Engineer.ClearEngineerTracking(oUnit)
        --Unpause engineers who are about to be cleared
        if oUnit[M28UnitInfo.refbPaused] then
            M28UnitInfo.PauseOrUnpauseEnergyUsage(oUnit, false)
        end
    end

    --Clear any micro flag
    oUnit[M28UnitInfo.refbSpecialMicroActive] = nil

    --Clear orders:
    IssueClearCommands({oUnit})

    --Unit name
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit) end
end

function RefreshUnitOrderTracking()  end --Just used to easily find UpdateRecordedOrders
function UpdateRecordedOrders(oUnit)
    --Checks a unit's command queue and removes items if we have fewer items than we recorded
    if not(oUnit[reftiLastOrders]) then
        oUnit[reftiLastOrders] = nil
        oUnit[refiOrderCount] = 0
    else
        if (oUnit[refiOrderCount] or 0) == 0 then
            oUnit[refiOrderCount] = table.getn(oUnit[reftiLastOrders])
        end
        local tCommandQueue
        if oUnit.GetCommandQueue then tCommandQueue = oUnit:GetCommandQueue() end
        local iCommandQueue = 0
        if tCommandQueue then iCommandQueue = table.getn(tCommandQueue) end
        if iCommandQueue < oUnit[refiOrderCount] then
            if iCommandQueue == 0 then
                oUnit[reftiLastOrders] = nil
                oUnit[refiOrderCount] = 0
            else
                local iRevisedIndex = 1
                local iTableSize = oUnit[refiOrderCount]
                local iOrdersToRemove = oUnit[refiOrderCount] - iCommandQueue

                for iOrigIndex=1, iTableSize do
                    if oUnit[reftiLastOrders][iOrigIndex] then
                        if iOrigIndex > iOrdersToRemove then
                            --We want to keep the entry; Move the original index to be the revised index number (so if e.g. a table of 1,2,3 removed 2, then this would've resulted in the revised index being 2 (i.e. it starts at 1, then icnreases by 1 for the first valid entry); this then means we change the table index for orig index 3 to be 2
                            if (iOrigIndex ~= iRevisedIndex) then
                                oUnit[reftiLastOrders][iRevisedIndex] = oUnit[reftiLastOrders][iOrigIndex]
                                oUnit[reftiLastOrders][iOrigIndex] = nil
                            end
                            iRevisedIndex = iRevisedIndex + 1 --i.e. this will be the position of where the next value that we keep will be located
                        else
                            oUnit[reftiLastOrders][iOrigIndex] = nil
                            oUnit[refiOrderCount] = oUnit[refiOrderCount] - 1
                        end
                    end
                end
            end
        end
    end
end

function IssueTrackedMove(oUnit, tOrderPosition, iDistanceToReissueOrder, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --If we are close enough then issue the order again - consider the first order given if not to add to existing queue
    local tLastOrder

    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit) == 'url020511' and GetGameTimeSeconds() >= 1450 then LOG('IssueTrackedMove: tLastOrder reprs='..reprs(tLastOrder)..'; tOrderPosition='..repru(tOrderPosition)..'; iDistanceToReissueOrder='..(iDistanceToReissueOrder or 'nil')..'; bAddToExistingQueue='..tostring(bAddToExistingQueue)..'; bOverrideMicroOrder='..tostring(bOverrideMicroOrder or false)..'; Unit has micro active='..tostring(oUnit[M28UnitInfo.refbSpecialMicroActive] or false)) end
    if not(tLastOrder and tLastOrder[subrefiOrderType] == refiOrderIssueMove and iDistanceToReissueOrder and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) < iDistanceToReissueOrder) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive]))  then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueMove, [subreftOrderPosition] = {tOrderPosition[1], tOrderPosition[2], tOrderPosition[3]}})
        IssueMove({oUnit}, tOrderPosition)
        if oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit) == 'url020511' and GetGameTimeSeconds() >= 1450 then LOG('IssueTrackedMove: Just given move order to '..oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit)..' to move to '..repru(tOrderPosition)) end
    end
    if M28Config.M28ShowUnitNames and tLastOrder[subrefiOrderType] then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end

end

function IssueTrackedAggressiveMove(oUnit, tOrderPosition, iDistanceToReissueOrder, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --If we are close enough then issue the order again
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if not(tLastOrder and tLastOrder[subrefiOrderType] == refiOrderIssueAggressiveMove and iDistanceToReissueOrder and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) < iDistanceToReissueOrder) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueAggressiveMove, [subreftOrderPosition] = {tOrderPosition[1], tOrderPosition[2], tOrderPosition[3]}})
        IssueAggressiveMove({oUnit}, tOrderPosition)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function PatrolPath(oUnit, tPath, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    --If the unit's last movement point isnt the first point in the path, then will reissue orders, with the path start point based on the estimated last path that it got to
    local sFunctionRef = 'PatrolPath'
    local bDebugMessages = false if M28Profiler.bGlobalDebugOverride == true then   bDebugMessages = true end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerStart)
    if bDebugMessages == true then LOG(sFunctionRef..': Considering unit '..oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit)..'; Last orders='..repru(oUnit[reftiLastOrders])..'; First point on path='..repru(tPath[1])..'; Will now refresh last orders') end
    UpdateRecordedOrders(oUnit)

    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]] end
    if bDebugMessages == true then LOG(sFunctionRef..': Unit orders after update='..repru(oUnit[reftiLastOrders])..'; Last order='..repru(tLastOrder)..'; Is the last order a move order='..tostring(tLastOrder[subrefiOrderType] == refiOrderIssueMove)..'; Last order position='..repru(tLastOrder[subreftOrderPosition])..'; tLastOrder pos 2 of table='..repru(tLastOrder[2])..'; Dist between path1 nd last order position='..M28Utilities.GetDistanceBetweenPositions(tPath[1], (tLastOrder[subreftOrderPosition] or {0,0,0}))) end

    if (not(tLastOrder) or not(tLastOrder[subrefiOrderType] == refiOrderIssueMove) or M28Utilities.GetDistanceBetweenPositions(tPath[1], tLastOrder[subreftOrderPosition]) > 1) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        --Our last active order isn't to move to the first point in the path, so will be reissuing the path
        if bDebugMessages == true then LOG(sFunctionRef..'; Will reissue orders to move along the path based on the closest point') end

        --first decide on start point for the path - pick the point closest to the unit
        local iClosestDist = 10000
        local iClosestPathRef
        local iCurDist
        for iPathRef, tPosition in tPath do
            iCurDist = M28Utilities.GetDistanceBetweenPositions(oUnit:GetPosition(), tPosition)
            if iCurDist < iClosestDist then
                iClosestDist = iCurDist
                iClosestPathRef = iPathRef
            end
        end

        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end

        for iPath = iClosestPathRef, table.getn(tPath) do
            local tOrderPosition = {tPath[iPath][1], tPath[iPath][2], tPath[iPath][3]}
            table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueMove, [subreftOrderPosition] = {tOrderPosition[1], tOrderPosition[2], tOrderPosition[3]}})
            oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
            IssueMove({oUnit}, tOrderPosition)
        end
        --Make the unit go to the first point on the path as its last order
        local tOrderPosition = {tPath[1][1], tPath[1][2], tPath[1][3]}
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueMove, [subreftOrderPosition] = {tOrderPosition[1], tOrderPosition[2], tOrderPosition[3]}})
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        IssueMove({oUnit}, tOrderPosition)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
    M28Profiler.FunctionProfiler(sFunctionRef, M28Profiler.refProfilerEnd)
end

function IssueTrackedAttackMove(oUnit, tOrderPosition, iDistanceToReissueOrder, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --If we are close enough then issue the order again
    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]] end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueAggressiveMove and iDistanceToReissueOrder and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) < iDistanceToReissueOrder) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueAggressiveMove, [subreftOrderPosition] = {tOrderPosition[1], tOrderPosition[2], tOrderPosition[3]}})
        IssueAggressiveMove({oUnit}, tOrderPosition)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedAttack(oUnit, oOrderTarget, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end


    if not(tLastOrder[subrefiOrderType] == refiOrderIssueAttack and oOrderTarget == tLastOrder[subrefoOrderTarget]) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueAttack, [subrefoOrderTarget] = oOrderTarget})
        IssueAttack({oUnit}, oOrderTarget)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedOvercharge(oUnit, oOrderTarget, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if not(tLastOrder[subrefiOrderType] == refiOrderOvercharge and oOrderTarget == tLastOrder[subrefoOrderTarget]) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderOvercharge, [subrefoOrderTarget] = oOrderTarget})
        IssueOverCharge({oUnit}, oOrderTarget)
    else --OC - add to queue if we think we are already overcharging, as in some cases we dont
        if (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
            if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
            oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
            table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderOvercharge, [subrefoOrderTarget] = oOrderTarget})
            IssueOverCharge({oUnit}, oOrderTarget)
        end
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedMoveAndBuild(oUnit, tBuildLocation, sOrderBlueprint, tMoveTarget, iDistanceToReorderMoveTarget, bAddToExistingQueue, sOptionalOrderDesc)
    UpdateRecordedOrders(oUnit)
    local bDontAlreadyHaveOrder = true
    local iLastOrderCount = 0
    if oUnit[reftiLastOrders] then
        iLastOrderCount = oUnit[refiOrderCount]
        if iLastOrderCount >= 2 then
            local tLastOrder = oUnit[reftiLastOrders][iLastOrderCount]
            if tLastOrder[subrefiOrderType] == refiOrderIssueBuild and sOrderBlueprint == tLastOrder[subrefsOrderBlueprint] and M28Utilities.GetDistanceBetweenPositions(tBuildLocation, tLastOrder[subreftOrderPosition]) <= 0.5 then
                local tSecondLastOrder = oUnit[reftiLastOrders][iLastOrderCount - 1]
                if tSecondLastOrder[subrefiOrderType] == refiOrderIssueMove and M28Utilities.GetDistanceBetweenPositions(tMoveTarget, tSecondLastOrder[subreftOrderPosition]) < (iDistanceToReorderMoveTarget or 0.01) then
                    bDontAlreadyHaveOrder = false
                end
            end
        end
    end
    --LOG('IssueTrackedMoveAndBuild: oUnit='..oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit)..'; bDontAlreadyHaveOrder='..tostring(bDontAlreadyHaveOrder or false))
    if bDontAlreadyHaveOrder then
        if not(bAddToExistingQueue) then
            --LOG('IssueTrackedMoveAndBuild: Will clear commands of the unit')
            IssueTrackedClearCommands(oUnit)
        end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueMove, [subreftOrderPosition] = {tMoveTarget[1], tMoveTarget[2], tMoveTarget[3]}})
        IssueMove({oUnit}, tMoveTarget)

        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueBuild, [subrefsOrderBlueprint] = sOrderBlueprint, [subreftOrderPosition] = {tBuildLocation[1], tBuildLocation[2], tBuildLocation[3]}})
        IssueBuildMobile({ oUnit }, tBuildLocation, sOrderBlueprint, {})
        ForkThread(M28Engineer.TrackQueuedBuilding, oUnit, sOrderBlueprint, tBuildLocation)
        --LOG('Sent an issuebuildmobile order to the unit')
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedBuild(oUnit, tOrderPosition, sOrderBlueprint, bAddToExistingQueue, sOptionalOrderDesc)
    UpdateRecordedOrders(oUnit)
    local tLastOrder

    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueBuild and sOrderBlueprint == tLastOrder[subrefsOrderBlueprint] and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) <= 0.5) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueBuild, [subrefsOrderBlueprint] = sOrderBlueprint, [subreftOrderPosition] = {tOrderPosition[1], tOrderPosition[2], tOrderPosition[3]}})
        IssueBuildMobile({ oUnit }, tOrderPosition, sOrderBlueprint, {})
        ForkThread(M28Engineer.TrackQueuedBuilding, oUnit, sOrderBlueprint, tOrderPosition)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedFactoryBuild(oUnit, sOrderBlueprint, bAddToExistingQueue, sOptionalOrderDesc)
    UpdateRecordedOrders(oUnit)
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueFactoryBuild and sOrderBlueprint == tLastOrder[subrefsOrderBlueprint]) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueFactoryBuild, [subrefsOrderBlueprint] = sOrderBlueprint})
        IssueBuildFactory({ oUnit }, sOrderBlueprint, 1)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end


function IssueTrackedReclaim(oUnit, oOrderTarget, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder

    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if (not(tLastOrder[subrefiOrderType] == refiOrderIssueReclaim and oOrderTarget == tLastOrder[subrefoOrderTarget]) or (not(oUnit:IsUnitState('Reclaiming')))) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueReclaim, [subrefoOrderTarget] = oOrderTarget})
        IssueReclaim({oUnit}, oOrderTarget)
        if not(oOrderTarget[M28Engineer.reftUnitsReclaimingUs]) then oOrderTarget[M28Engineer.reftUnitsReclaimingUs] = {} end
        table.insert(oOrderTarget[M28Engineer.reftUnitsReclaimingUs], oUnit)
        if not(oUnit[M28Engineer.reftUnitsWeAreReclaiming]) then oUnit[M28Engineer.reftUnitsWeAreReclaiming] = {} end
        table.insert(oUnit[M28Engineer.reftUnitsWeAreReclaiming], oOrderTarget)

    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc..(oOrderTarget.UnitId or '')) end
end

function IssueTrackedGroundAttack(oUnit, tOrderPosition, iDistanceToReissueOrder, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --If we are close enough then issue the order again
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end

    if not(tLastOrder[subrefiOrderType] == refiOrderIssueGroundAttack and iDistanceToReissueOrder and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) < iDistanceToReissueOrder) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueGroundAttack, [subreftOrderPosition] = {tOrderPosition[1], tOrderPosition[2], tOrderPosition[3]}})
        IssueAttack({oUnit}, tOrderPosition)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedGuard(oUnit, oOrderTarget, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueGuard and oOrderTarget == tLastOrder[subrefoOrderTarget]) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueGuard, [subrefoOrderTarget] = oOrderTarget})
        if not(oOrderTarget[M28UnitInfo.reftoUnitsAssistingThis]) then oOrderTarget[M28UnitInfo.reftoUnitsAssistingThis] = {} end
        table.insert(oOrderTarget[M28UnitInfo.reftoUnitsAssistingThis], oUnit)
        IssueGuard({oUnit}, oOrderTarget)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedRepair(oUnit, oOrderTarget, bAddToExistingQueue, sOptionalOrderDesc, bOverrideMicroOrder)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueRepair and oOrderTarget == tLastOrder[subrefoOrderTarget]) and (bOverrideMicroOrder or not(oUnit[M28UnitInfo.refbSpecialMicroActive])) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueRepair, [subrefoOrderTarget] = oOrderTarget})
        IssueRepair({oUnit}, oOrderTarget)
        --Track against the unit we are repairing if it is under construction
        if oOrderTarget:GetFractionComplete() < 1 then
            if not(oOrderTarget[toUnitsOrderedToRepairThis]) then
                oOrderTarget[toUnitsOrderedToRepairThis] = {}
            end
            table.insert(oOrderTarget[toUnitsOrderedToRepairThis], oUnit)
        end
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedUpgrade(oUnit, sUpgradeRef, bAddToExistingQueue, sOptionalOrderDesc)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if not(tLastOrder[subrefiOrderType] == refiOrderUpgrade and sUpgradeRef == tLastOrder[subrefsOrderBlueprint]) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderUpgrade, [subrefsOrderBlueprint] = sUpgradeRef})
        IssueUpgrade({oUnit}, sUpgradeRef)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedEnhancement(oUnit, sUpgradeRef, bAddToExistingQueue, sOptionalOrderDesc)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    if not(tLastOrder[subrefiOrderType] == refiOrderEnhancement and sUpgradeRef == tLastOrder[subrefsOrderBlueprint]) and not(oUnit:IsUnitState('Upgrading')) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
        oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderEnhancement, [subrefsOrderBlueprint] = sUpgradeRef})
        IssueScript({oUnit}, {TaskName = 'EnhanceTask', Enhancement = sUpgradeRef})
        M28Team.UpdateUpgradeTrackingOfUnit(oUnit, false, sUpgradeRef)
    end
    if M28Config.M28ShowUnitNames then UpdateUnitNameForOrder(oUnit, sOptionalOrderDesc) end
end

function IssueTrackedKillUnit(oUnit)
    IssueTrackedClearCommands(oUnit)
    if oUnit[reftiLastOrders] then
        if bAddToExistingQueue then
            tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
        else tLastOrder = oUnit[reftiLastOrders][1]
        end
    end
    oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
    table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderKill})
    oUnit:Kill()
end

--[[function IssueTrackedOrder(oUnit, iOrderType, tOrderPosition, oOrderTarget, sOrderBlueprint)
--Decided not to implement below as hopefully using separate functions should be better performance wise, and also issueformmove and aggressive move will require a table of units instead of individual units if they ever get implemented
    --tOrderPosition - this should only be completed if it is requried for the order
    if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} oUnit[refiOrderCount] = 0 end
    oUnit[refiOrderCount] = oUnit[refiOrderCount] + 1
    table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = iOrderType, [subreftOrderPosition] = {tOrderPosition[1], tOrderPosition[2], tOrderPosition[3]}, [subrefoOrderTarget] = oOrderTarget, [subrefsOrderBlueprint] = sOrderBlueprint})
    if iOrderType == refiOrderIssueMove then
        IssueMove({oUnit}, tOrderPosition)
    elseif iOrderType == refiOrderIssueAggressiveMove then
        IssueAggressiveMove({oUnit}, tOrderPosition)
    elseif iOrderType == refiOrderIssueBuild then
        IssueBuildMobile({oUnit}, tOrderPosition, sOrderBlueprint, {})
    elseif iOrderType == refiOrderIssueReclaim then
        IssueReclaim({oUnit}, oOrderTarget)
    elseif iOrderType == refiOrderIssueAttack then
        IssueAttack({oUnit}, oOrderTarget)
    elseif iOrderType == refiOrderIssueGroundAttack then
        IssueAttack({oUnit}, tOrderPosition)
    elseif iOrderType == refiOrderIssueGuard then
        IssueGuard({oUnit}, oOrderTarget)
    elseif iOrderType == refiOrderIssueFormMove then
        IssueFormMove({oUnit}, tOrderPosition)
    elseif iOrderType == refiOrderIssueAggressiveFormMove then
        IssueFormAggressiveMove({oUnit}, tOrderPosition)
    elseif iOrderType == refiOrderIssueRepair then
        IssueRepair({oUnit}, oOrderTarget)
    elseif iOrderType == refiOrderOvercharge then
        IssueOvercharge({oUnit}, oOrderTarget)
    elseif iOrderType == refiOrderUpgrade then
        IssueScript({oUnit}, {TaskName = 'EnhanceTask', Enhancement = sOrderBlueprint})
    elseif iOrderType == refiOrderTransportLoad then
        IssueTransportLoad({oUnit}, oOrderTarget) --oUnit is e.g. the engineer, oOrderTarget is the transport it should bel oaded onto
    elseif iOrderType == refiOrderIssueGroundAttack then
        IssueTransportUnload({oUnit}, tOrderPosition) --e.g. oUnit is the transport
    end
end--]]

function ClearAnyRepairingUnits(oUnitBeingRepaired)
    --LOG('Is table of units ordered to repair oUnitBeingRepaired='..oUnitBeingRepaired.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnitBeingRepaired)..' empty='..tostring(M28Utilities.IsTableEmpty(oUnitBeingRepaired[toUnitsOrderedToRepairThis])))
    if oUnitBeingRepaired[toUnitsOrderedToRepairThis] then
        if M28Utilities.IsTableEmpty(oUnitBeingRepaired[toUnitsOrderedToRepairThis]) == false then
            for iUnit, oUnit in oUnitBeingRepaired[toUnitsOrderedToRepairThis] do
                if M28UnitInfo.IsUnitValid(oUnit) then
                    --Is this unit still trying to repair this?
                    UpdateRecordedOrders(oUnit)
                    --LOG('Considering if oUnit='..oUnit.UnitId..M28UnitInfo.GetUnitLifetimeCount(oUnit)..' is still repairing; Last orders='..reprs(oUnit[reftiLastOrders]))
                    if oUnit[reftiLastOrders] then
                        local tLastOrder = oUnit[reftiLastOrders][oUnit[refiOrderCount]]
                        if tLastOrder[subrefiOrderType] == refiOrderIssueRepair and oUnitBeingRepaired == tLastOrder[subrefoOrderTarget] then
                            oUnit[reftiLastOrders] = nil --Clear here so we avoid the logic for lcearing in trackedclearcommands
                            IssueTrackedClearCommands(oUnit)
                        end

                    end
                end
            end
        end
        oUnitBeingRepaired[toUnitsOrderedToRepairThis] = nil
    end
end