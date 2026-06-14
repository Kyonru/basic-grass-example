local defaultGraph = require("player.action_graph")

local PlayerController = {}
PlayerController.__index = PlayerController

function PlayerController:new(player, input, fsm, options)
	options = options or {}

	return setmetatable({
		player = player,
		input = input,
		fsm = fsm,
		graph = options.graph or defaultGraph,
		moveAction = options.moveAction or "move",
		runAction = options.runAction or "run",
		lastIntent = nil,
		lastEvent = nil,
		lastFrom = nil,
		lastTo = nil,
	}, self)
end

function PlayerController:isActionLocked()
	return self.graph:isLocked(self.fsm.current)
end

function PlayerController:_fire(event, intent, context)
	if not event or not self.fsm:can(event) then
		return false
	end

	local from = self.fsm.current
	local ok, to = self.fsm:can(event)
	if not ok then
		return false
	end

	self.lastIntent = intent
	self.lastEvent = event
	self.lastFrom = from
	self.lastTo = to

	return self.fsm[event](self.fsm, {
		intent = intent,
		from = from,
		to = to,
		context = context,
	})
end

function PlayerController:request(intent, context)
	local event = self.graph:resolve(self.fsm.current, intent)
	return self:_fire(event, intent, context)
end

function PlayerController:_getMove()
	local x, y = self.input:get(self.moveAction)

	if type(x) == "table" then
		return x[1] or x.x or 0, x[2] or x.y or 0
	end

	return x or 0, y or 0
end

function PlayerController:resolveLocomotion()
	if self:isActionLocked() then
		return false
	end

	local x, y = self:_getMove()
	local hasMove = x ~= 0 or y ~= 0

	if hasMove then
		if self.input:down(self.runAction) then
			return self:_fire("run", "run")
		end

		return self:_fire("walk", "walk")
	end

	return self:_fire("idle", "idle")
end

function PlayerController:finishAction()
	if self.fsm:can("finish") then
		self:_fire("finish", "finish")
	end

	return self:resolveLocomotion()
end

function PlayerController:update(dt)
	if self.input.update then
		self.input:update(dt)
	end

	if self.input:pressed("roll") and self:request("roll") then
		return
	end

	if self.input:pressed("attack") and self:request("attack") then
		return
	end

	self:resolveLocomotion()
end

return PlayerController
