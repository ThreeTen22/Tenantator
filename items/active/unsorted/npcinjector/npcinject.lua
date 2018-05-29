require "/scripts/interp.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/util.lua"

NpcInject = WeaponAbility:new()

function NpcInject:init()
  if not storage then storage = {} end
  self.debug = true
  util.setDebug(true)
  util.debugLog("Ininit")
  
  self.weapon:setStance(self.stances.idle)
  self.cooldownTimer = 0
  self.tenants = nil
  self.tenantPortraits = nil
  self.typeConfig = nil
  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end

  storage.stagehandId = storage.stagehandId or nil

  message.setHandler("npcinjector.onStagehandSuccess", function(_,_,id, tenants, tenantPortraits, typeConfig)
    util.debugLog("npcinjector.onStagehandSuccess ")
    self.tenants = tenants
    self.tenantPortraits = tenantPortraits
    self.typeConfig = typeConfig
    storage.stagehandId = id
    return true
  end)
  message.setHandler("npcinjector.onStagehandFailed", function(_,_,args)
    util.debugLog("npcinjector.onStagehandFailed")
    storage.stagehandId = nil
    storage.spawner = nil

    self.cooldownTimer = self.cooldownTime
  end)

  message.setHandler("npcinjector.onPaneDismissed", function(_,_,...)
    util.debugLog("npcinjector.onPaneDismissed")
    storage.spawner = nil
    storage.stagehandId = nil

    --self.cooldownTimer = self.cooldownTime
  end)

  animator.setGlobalTag("absorbed", string.format("%s", 0))
end


function NpcInject:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)

  self.cooldownTimer = math.max(self.cooldownTimer - dt, 0.0)

  if self.fireMode == "primary"
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0 then

    if not storage.spawner then
      self:setState(self.scan)
    elseif world.entityExists(storage.stagehandId or -1) then
      self:setState(self.absorb, storage.stagehandId, storage.spawner)
    else
      animator.playSound("error")
      self.cooldownTimer = self.cooldownTime
    end
  end
  if self.fireMode == "alt" then
    --DEBUG:  DONT KEEP
    
    --self.weapon:setStance(self.stances.idle)
    self.cooldownTimer = 0
    storage.spawner = nil
    storage.stagehandId = nil
    
  end

  if storage.spawner and storage.stagehandId 
  and not self.weapon.currentAbility
  and self.cooldownTimer == 0
  and world.entityExists(storage.spawner.deedId) 
  and world.entityExists(storage.stagehandId) then

    animator.setGlobalTag("absorbed", string.format("%s", 3))
    self:setState(self.absorb, stagehandId, storage.spawner)

  end

  --[[
  local mag = world.magnitude(mcontroller.position(), activeItem.ownerAimPosition())
  if self.fireMode == "alt"
    and not self.weapon.currentAbility
    and self.cooldownTimer == 0
    and #storage.spawner > 0
    and mag > vec2.mag(self.weapon.muzzleOffset) and mag < self.maxRange
    and not world.lineTileCollision(self:firePosition(), activeItem.ownerAimPosition()) then

    self:setState(self.fire)
  end
  --]]
end

function NpcInject:scan()
  animator.playSound("scan")
  animator.playSound("scanning", -1)

  local promises = {}
  local scanCount = 1
  while self.fireMode == "primary" do
    local objects = world.objectQuery(activeItem.ownerAimPosition(), 2, {order = "nearest" })
    objects = util.filter(objects, 
      function(objectId)
        local position = world.entityPosition(objectId)
        if world.lineTileCollision(self:firePosition(), position) then
          return false
        end
        local mag = world.magnitude(mcontroller.position(), position)
        if mag > self.maxRange or mag < vec2.mag(self.weapon.muzzleOffset) then
          return false
        end
        if world.getObjectParameter(objectId, "category") ~= "spawner" then
          return false
        end
        return true
    end)
    if #objects > 0 then
      local spawner = {}
      local deedId = objects[1]
      if not storage.spawner then
        
        world.sendEntityMessage((storage.stagehandId or -1), "colonyManager.die")
        storage.stagehandId = nil
       
        local dUuid = world.entityUniqueId(deedId)
        local pUuid = player.uniqueId()
        local position = world.entityPosition(deedId)
        spawner = world.getObjectParameter(deedId, "deed") or {}
        spawner.position = position
        spawner.deedId = deedId
        spawner.attachPoint = {0,0}
        storage.spawner = spawner
        
        world.spawnStagehand(mcontroller.position(), "colonymanager", 
        { deedId = deedId,
          deedPosition = position,
          deedUuid=dUuid, 
          playerUuid=pUuid
        })


        self:setState(self.absorb, stagehandId, spawner)
        return true
      else
        return false
      end
    end
    coroutine.yield()
  end

  animator.stopAllSounds("scanning")
  animator.playSound("scanend")
end


function NpcInject:absorb(stagehandId, spawner)
  animator.stopAllSounds("scanning")
  self.weapon:setStance(self.stances.absorb)
  animator.playSound("start")
  animator.playSound("loop", -1)
  animator.setGlobalTag("absorbed", string.format("%s", 3))

  local spawnerPos = {0, 0}


  local timer = 0
  while timer < self.beamReturnTime do
    if world.entityExists(spawner.deedId) then
      spawnerPos = vec2.add(world.entityPosition(spawner.deedId), spawner.attachPoint)
    end
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, spawnerPos)
    local offset = self:beamPosition(spawnerPos)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)

    timer = timer + script.updateDt()
    coroutine.yield()
  end

  local stoppedBeam = false
  local scanTimer = 1
  animator.stopAllSounds("loop")
  
  local dUuid = world.entityUniqueId(spawner.deedId)
  local pUuid = player.uniqueId()
 
  while not world.entityExists(storage.stagehandId or -1) and storage.spawner do
    coroutine.yield()
  end

  if storage.spawner and not stagehandId then
    local deedpane = root.assetJson("/interface/scripted/deedmenu/deedpane.config")
    local tenants = self.tenants
    local tenantPortraits = self.tenantPortraits
    local typeConfig = self.typeConfig
    self.tenants, self.tenantPortraits, self.typeConfig = {}, {}, {}
    deedpane.deedUuid = dUuid
    deedpane.playerUuid = pUuid
    deedpane.stagehandId = storage.stagehandId
    deedpane.deedId = storage.spawner.deedId
    deedpane.deedPosition = spawnerPos
    deedpane.tenants = tenants
    deedpane.tenantPortraits = tenantPortraits
    deedpane.configs = typeConfig
    activeItem.interact("ScriptPane", deedpane, storage.stagehandId)
  end

  while world.entityExists(storage.stagehandId or -1)
  do
    self.weapon.aimAngle, self.weapon.aimDirection = activeItem.aimAngleAndDirection(self.weapon.aimOffset, spawnerPos)
    spawnerPos = vec2.add(world.entityPosition(spawner.deedId), spawner.attachPoint)
    local offset = self:beamPosition(spawnerPos)
    self:drawBeam(vec2.add(self:firePosition(), offset), false)

    coroutine.yield()
  end

  animator.stopAllSounds("loop")
  animator.playSound("stop")

  timer = self.beamReturnTime
  while timer > 0 do
    local offset = self:beamPosition(spawnerPos)
    self:drawBeam(vec2.add(self:firePosition(), vec2.mul(offset, timer / self.beamReturnTime)), false)

    timer = timer - script.updateDt()

    coroutine.yield()
  end
  animator.setGlobalTag("absorbed", string.format("%s", 0))
  self.cooldownTimer = self.cooldownTime
end

function NpcInject:fire()

end

function NpcInject:drawBeam(endPos, didCollide)
  local newChain = copy(self.chain)
  newChain.startOffset = self.weapon.muzzleOffset
  newChain.endPosition = endPos

  if didCollide then
    newChain.endSegmentImage = nil
  end

  activeItem.setScriptedAnimationParameter("chains", {newChain})
end

function NpcInject:beamPosition(aimPosition)
  local offset = vec2.mul(
    vec2.withAngle(
      self.weapon.aimAngle, 
      math.max(
        0, 
        world.magnitude(
          aimPosition, 
          self:firePosition()))
    ), {self.weapon.aimDirection, 1}
  )
  if vec2.dot(offset, world.distance(aimPosition, self:firePosition())) < 0 then
    -- don't draw the beam backwards
    offset = {0,0}
  end
  return offset
end

function NpcInject:firePosition()
  return vec2.add(mcontroller.position(), activeItem.handPosition(self.weapon.muzzleOffset))
end

function NpcInject:aimVector(inaccuracy)
  local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
  aimVector[1] = aimVector[1] * mcontroller.facingDirection()
  return aimVector
end

function NpcInject:uninit()
  self:reset()
end

function NpcInject:reset()
  util.debugLog("npcinject: reset")
  animator.stopAllSounds("loop")
  self.weapon:setDamage()
  activeItem.setScriptedAnimationParameter("chains", {})
end
