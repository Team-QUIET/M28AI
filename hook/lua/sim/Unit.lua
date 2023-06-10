---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 02/12/2022 09:13
---
local M28Events = import('/mods/M28AI/lua/AI/M28Events.lua')

do --Per Balthazaar - encasing the code in do .... end means that you dont have to worry about using unique variables
    local M28OldUnit = Unit
    Unit = Class(M28OldUnit) {
        OnKilled = function(self, instigator, type, overkillRatio) --NOTE: For some reason this doesnt run a lot of the time; onkilledunit is more reliable
            M28Events.OnKilled(self, instigator, type, overkillRatio)
            M28OldUnit.OnKilled(self, instigator, type, overkillRatio)
        end,
        OnReclaimed = function(self, reclaimer)
            M28Events.OnKilled(self, reclaimer)
            M28OldUnit.OnReclaimed(self, reclaimer)
        end,
        OnDecayed = function(self)
            LOG('OnDecayed: Time='..GetGameTimeSeconds()..'; self.UnitId='..(self.UnitId or 'nil'))
            M28Events.OnUnitDeath(self)
            M28OldUnit.OnDecayed(self)
        end,
        OnKilledUnit = function(self, unitKilled, massKilled)
            M28Events.OnKilled(unitKilled, self)
            M28OldUnit.OnKilledUnit(self, unitKilled, massKilled)
        end,
        OnDestroy = function(self)
            --LOG('OnDestroy: Time='..GetGameTimeSeconds()..'; self.UnitId='..(self.UnitId or 'nil'))
            M28Events.OnUnitDeath(self)
            M28OldUnit.OnDestroy(self)
        end,
        --[[OnFailedToBeBuilt = function(self)
            LOG('OnFailedToBeBuilt: Time='..GetGameTimeSeconds()..'; self.UnitId='..(self.UnitId or 'nil'))
            M28OldUnit.OnFailedToBeBuilt(self)
        end,--]]
        OnDestroy = function(self)
            M28Events.OnUnitDeath(self) --Any custom code we want to run
            M28OldUnit.OnDestroy(self) --Normal code
        end,
        OnWorkEnd = function(self, work)
            M28Events.OnWorkEnd(self, work)
            M28OldUnit.OnWorkEnd(self, work)
        end,
        OnDamage = function(self, instigator, amount, vector, damageType)
            M28OldUnit.OnDamage(self, instigator, amount, vector, damageType)
            M28Events.OnDamaged(self, instigator) --Want this after just incase our code messes things up
        end,
        OnSiloBuildEnd = function(self, weapon)
            M28OldUnit.OnSiloBuildEnd(self, weapon)
            M28Events.OnMissileBuilt(self, weapon)
        end,
        OnStartBuild = function(self, built, order, ...)
            ForkThread(M28Events.OnConstructionStarted, self, built, order)
            return M28OldUnit.OnStartBuild(self, built, order, unpack(arg))
        end,
        OnStartReclaim = function(self, target)
            ForkThread(M28Events.OnReclaimStarted, self, target)
            return M28OldUnit.OnStartReclaim(self, target)
        end,
        OnStopReclaim = function(self, target)
            ForkThread(M28Events.OnReclaimFinished, self, target)
            return M28OldUnit.OnStopReclaim(self, target)
        end,

        OnStopBuild = function(self, unit)
            if unit and not(unit.Dead) and unit.GetFractionComplete and unit:GetFractionComplete() == 1 then
                ForkThread(M28Events.OnConstructed, self, unit)
            end
            return M28OldUnit.OnStopBuild(self, unit)
        end,

        OnAttachedToTransport = function(self, transport, bone)
            ForkThread(M28Events.OnTransportLoad, self, transport, bone)
            return M28OldUnit.OnAttachedToTransport(self, transport, bone)
        end,
        OnDetachedFromTransport = function(self, transport, bone)
            ForkThread(M28Events.OnTransportUnload, self, transport, bone)
            return M28OldUnit.OnDetachedFromTransport(self, transport, bone)
        end,
        OnDetectedBy = function(self, index)

            ForkThread(M28Events.OnDetectedBy, self, index)
            return M28OldUnit.OnDetectedBy(self, index)
        end,
        OnCreate = function(self)
            M28OldUnit.OnCreate(self)
            ForkThread(M28Events.OnCreate, self)
        end,
        CreateEnhancement = function(self, enh)
            ForkThread(M28Events.OnEnhancementComplete, self, enh)
            return M28OldUnit.CreateEnhancement(self, enh)
        end,
        OnMissileImpactTerrain = function(self, target, position)
            ForkThread(M28Events.OnMissileImpactTerrain, self, target, position)
            return M28OldUnit.OnMissileImpactTerrain(self, target, position)
        end,
        OnMissileIntercepted = function(self, target, defense, position)
            ForkThread(M28Events.OnMissileIntercepted, self, target, defense, position)
        end,
    }
end


--Hooks not used:
--[[CreateEnhancementEffects = function(self, enhancement)
            local bp = self:GetBlueprint().Enhancements[enhancement]
            local effects = TrashBag()
            local bpTime = bp.BuildTime
            local bpBuildCostEnergy = bp.BuildCostEnergy
            if bpTime == nil then LOG('ERROR: CreateEnhancementEffects: bp.bpTime is nil; bp='..self:GetBlueprint().BlueprintId)
                bpTime = 1 end --Avoid infinite loop
            if bpBuildCostEnergy == nil then
                LOG('ERROR: CreateEnhancementEffects: bp.BuildCostEnergy is nil; bp='..self:GetBlueprint().BlueprintId)
                bpBuildCostEnergy = 1 end
            local scale = math.min(4, math.max(1, (bpBuildCostEnergy / bpTime or 1) / 50))

            if bp.UpgradeEffectBones then
                for _, v in bp.UpgradeEffectBones do
                    if self:IsValidBone(v) then
                        EffectUtilities.CreateEnhancementEffectAtBone(self, v, self.UpgradeEffectsBag)
                    end
                end
            end

            if bp.UpgradeUnitAmbientBones then
                for _, v in bp.UpgradeUnitAmbientBones do
                    if self:IsValidBone(v) then
                        EffectUtilities.CreateEnhancementUnitAmbient(self, v, self.UpgradeEffectsBag)
                    end
                end
            end

            for _, e in effects do
                e:ScaleEmitter(scale)
                self.UpgradeEffectsBag:Add(e)
            end
        end, ]]--