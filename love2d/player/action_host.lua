local PlayerActionHost = {}
PlayerActionHost.__index = PlayerActionHost

function PlayerActionHost:new(animations)
	return setmetatable({
		animations = animations or {},
		currentAnimation = nil,
		actionTimer = nil,
		controller = nil,
	}, self)
end

function PlayerActionHost:setController(controller)
	self.controller = controller
end

function PlayerActionHost:setAnimation(name)
	if self.currentAnimation == name then
		return
	end

	self.currentAnimation = name

	local animation = self.animations[name]
	if animation and animation.gotoFrame then
		animation:gotoFrame(1)
	end
end

function PlayerActionHost:enterTimedAction(name, duration)
	self:setAnimation(name)
	self.actionTimer = duration
end

function PlayerActionHost:update(dt)
	if self.actionTimer then
		self.actionTimer = self.actionTimer - dt

		if self.actionTimer <= 0 then
			self.actionTimer = nil

			if self.controller then
				self.controller:finishAction()
			end
		end
	end

	local animation = self.animations[self.currentAnimation]
	if animation and animation.update then
		animation:update(dt)
	end
end

return PlayerActionHost
