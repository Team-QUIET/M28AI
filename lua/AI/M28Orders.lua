---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 30/11/2022 22:36
---
local M28Utilities = import('/mods/M28AI/lua/AI/M28Utilities.lua')


--Order info
reftiLastOrders = 'M28OrdersLastOrders' --Against unit, table first of the order number (1 = first order given, 2 = 2nd etc., qhere they were queued), which returns a table containing all the details of the order (including the order type per the below reference integers)

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
refiOrderUpgrade = 11
refiOrderTransportLoad = 12
refiOrderIssueGroundAttack = 13

function IssueTrackedClearCommands(oUnit)
    oUnit[reftiLastOrders] = nil
    IssueClearCommands({oUnit})
end

local function UpdateRecordedOrders(oUnit)
    --Checks a unit's command queue and removes items if we have fewer items than we recorded
    local iRecordedOrders
    if not(oUnit[reftiLastOrders]) then
        oUnit[reftiLastOrders] = nil
        iRecordedOrders = 0
    else
        iRecordedOrders = table.getn(oUnit[reftiLastOrders])
        local tCommandQueue = oUnit:GetCommandQueue()
        local iCommandQueue = 0
        if tCommandQueue then iCommandQueue = table.getn(tCommandQueue) end
        if iCommandQueue < iRecordedOrders then
            local iOrdersToRemove = iRecordedOrders - iCommandQueue
            for iEntry = 1, iOrdersToRemove do
                oUnit[reftiLastOrders][iRecordedOrders] = nil
                iRecordedOrders = iRecordedOrders - 1
            end
        end
    end
end

function IssueTrackedMove(oUnit, tOrderPosition, iDistanceToReissueOrder, bAddToExistingQueue)
    UpdateRecordedOrders(oUnit)
    --If we are close enough then issue the order again
    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][table.getn(oUnit[reftiLastOrders])] end
    if not(tLastOrder and tLastOrder[subrefiOrderType] == refiOrderIssueMove and iDistanceToReissueOrder and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) < iDistanceToReissueOrder) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} end
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueMove, [subreftOrderPosition] = tOrderPosition})
        IssueMove({oUnit}, tOrderPosition)
    end
end

function IssueTrackedAttackMove(oUnit, tOrderPosition, iDistanceToReissueOrder, bAddToExistingQueue)
    UpdateRecordedOrders(oUnit)
    --If we are close enough then issue the order again
    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][table.getn(oUnit[reftiLastOrders])] end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueAggressiveMove and iDistanceToReissueOrder and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) < iDistanceToReissueOrder) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} end
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueAggressiveMove, [subreftOrderPosition] = tOrderPosition})
        IssueAggressiveMove({oUnit}, tOrderPosition)
    end
end

function IssueTrackedAttack(oUnit, oOrderTarget, bAddToExistingQueue)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][table.getn(oUnit[reftiLastOrders])] end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueAttack and oOrderTarget == tLastOrder[subrefoOrderTarget]) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} end
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueAttack, [subrefoOrderTarget] = oOrderTarget})
        IssueAttack({oUnit}, oOrderTarget)
    end
end

function IssueTrackedBuild(oUnit, tOrderPosition, sOrderBlueprint, bAddToExistingQueue)
    UpdateRecordedOrders(oUnit)
    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][table.getn(oUnit[reftiLastOrders])] end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueBuild and sOrderBlueprint == tLastOrder[subrefsOrderBlueprint] and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) <= 0.5) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} end
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueBuild, [subrefsOrderBlueprint] = sOrderBlueprint, [subreftOrderPosition] = tOrderPosition})
        IssueBuildMobile({ oUnit }, tOrderPosition, sOrderBlueprint, {})
    end
end

function IssueTrackedReclaim(oUnit, oOrderTarget, bAddToExistingQueue)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][table.getn(oUnit[reftiLastOrders])] end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueReclaim and oOrderTarget == tLastOrder[subrefoOrderTarget]) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} end
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueReclaim, [subrefoOrderTarget] = oOrderTarget})
        IssueReclaim({oUnit}, oOrderTarget)
    end
end

function IssueTrackedGroundAttack(oUnit, tOrderPosition, iDistanceToReissueOrder, bAddToExistingQueue)
    UpdateRecordedOrders(oUnit)
    --If we are close enough then issue the order again
    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][table.getn(oUnit[reftiLastOrders])] end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueGroundAttack and iDistanceToReissueOrder and M28Utilities.GetDistanceBetweenPositions(tOrderPosition, tLastOrder[subreftOrderPosition]) < iDistanceToReissueOrder) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} end
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueGroundAttack, [subreftOrderPosition] = tOrderPosition})
        IssueAttack({oUnit}, tOrderPosition)
    end
end

function IssueTrackedGuard(oUnit, oOrderTarget, bAddToExistingQueue)
    UpdateRecordedOrders(oUnit)
    --Issue order if we arent already trying to attack them
    local tLastOrder
    if oUnit[reftiLastOrders] then tLastOrder = oUnit[reftiLastOrders][table.getn(oUnit[reftiLastOrders])] end
    if not(tLastOrder[subrefiOrderType] == refiOrderIssueGuard and oOrderTarget == tLastOrder[subrefoOrderTarget]) then
        if not(bAddToExistingQueue) then IssueTrackedClearCommands(oUnit) end
        if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} end
        table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = refiOrderIssueGuard, [subrefoOrderTarget] = oOrderTarget})
        IssueGuard({oUnit}, oOrderTarget)
    end
end

--[[function IssueTrackedOrder(oUnit, iOrderType, tOrderPosition, oOrderTarget, sOrderBlueprint)
--Decided not to implement below as hopefully using separate functions should be better performance wise, and also issueformmove and aggressive move will require a table of units instead of individual units if they ever get implemented
    --tOrderPosition - this should only be completed if it is requried for the order
    if not(oUnit[reftiLastOrders]) then oUnit[reftiLastOrders] = {} end
    table.insert(oUnit[reftiLastOrders], {[subrefiOrderType] = iOrderType, [subreftOrderPosition] = tOrderPosition, [subrefoOrderTarget] = oOrderTarget, [subrefsOrderBlueprint] = sOrderBlueprint})
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