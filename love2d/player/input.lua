-- baton input config for the player.
-- Control names map to PlayerController defaults: a "move" pair plus the
-- "run", "roll", and "attack" controls it queries each frame.
local baton = require("lib.baton")

return function()
	return baton.new({
		controls = {
			left = { "key:left", "key:a", "axis:leftx-", "button:dpleft" },
			right = { "key:right", "key:d", "axis:leftx+", "button:dpright" },
			up = { "key:up", "key:w", "axis:lefty-", "button:dpup" },
			down = { "key:down", "key:s", "axis:lefty+", "button:dpdown" },
			run = { "key:lshift", "button:b" },
			roll = { "key:space", "button:a" },
			attack = { "key:j", "key:x", "button:x" },
		},
		pairs = {
			-- name MUST be "move" (PlayerController.moveAction default)
			move = { "left", "right", "up", "down" },
		},
		joystick = love.joystick.getJoysticks()[1],
	})
end
