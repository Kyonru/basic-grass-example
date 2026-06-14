local machine = require("lib.statemachine")
local defaultGraph = require("player.action_graph")

local PlayerFsm = {}

local function merge_callbacks(base, extra)
	for name, callback in pairs(extra or {}) do
		base[name] = callback
	end

	return base
end

local function build_callbacks(player, graph)
	local callbacks = {}

	for state, animationName in pairs(graph.animations) do
		callbacks["onenter" .. state] = function(fsm, event, from, to, context)
			local duration = graph.durations[to]

			if duration and player.enterTimedAction then
				player:enterTimedAction(animationName, duration, {
					event = event,
					from = from,
					to = to,
					context = context,
				})
			elseif player.setAnimation then
				player:setAnimation(animationName)
			end
		end
	end

	return callbacks
end

function PlayerFsm.create(player, options)
	options = options or {}

	local graph = options.graph or defaultGraph
	local callbacks = build_callbacks(player, graph)
	merge_callbacks(callbacks, options.callbacks)

	local fsm = machine.create({
		initial = options.initial or graph.initial,
		events = graph.events,
		callbacks = callbacks,
	})

	local initialAnimation = graph.animations[fsm.current]
	if initialAnimation and player.setAnimation then
		player:setAnimation(initialAnimation)
	end

	return fsm
end

return PlayerFsm
