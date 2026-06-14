local ActionGraph = {}

ActionGraph.initial = "idle"

ActionGraph.locked = {
	roll = true,
	slide = true,
	attack = true,
	running_attack = true,
}

ActionGraph.actionMap = {
	idle = {
		roll = "roll",
		attack = "attack",
	},

	walking = {
		roll = "roll",
		attack = "attack",
	},

	running = {
		roll = "slide",
		attack = "runningAttack",
	},
}

ActionGraph.events = {
	{ name = "idle", from = { "walking", "running" }, to = "idle" },
	{ name = "walk", from = { "idle", "running" }, to = "walking" },
	{ name = "run", from = { "idle", "walking" }, to = "running" },

	{ name = "roll", from = { "idle", "walking" }, to = "roll" },
	{ name = "slide", from = "running", to = "slide" },

	{ name = "attack", from = { "idle", "walking" }, to = "attack" },
	{ name = "runningAttack", from = "running", to = "running_attack" },

	{ name = "finish", from = { "roll", "slide", "attack", "running_attack" }, to = "idle" },
}

ActionGraph.animations = {
	idle = "idle",
	walking = "walk",
	running = "run",
	roll = "roll",
	slide = "slide",
	attack = "attack",
	running_attack = "running_attack",
}

ActionGraph.durations = {
	roll = 0.35,
	slide = 0.45,
	attack = 0.4,
	running_attack = 0.5,
}

function ActionGraph:isLocked(state)
	return self.locked[state] == true
end

function ActionGraph:resolve(state, intent)
	local stateActions = self.actionMap[state]
	return stateActions and stateActions[intent] or nil
end

return ActionGraph
