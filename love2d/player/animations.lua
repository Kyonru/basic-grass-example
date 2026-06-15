-- anim8 animation set for the player action host.
-- Keys MUST match the values in ActionGraph.animations:
--   idle, walk, run, roll, slide, attack, running_attack
-- Adjust frame size and the grid ranges below to fit your real spritesheet.
local anim8 = require("lib.anim8")

return function(sheet, opts)
	opts = opts or {}
	local fw = opts.frameWidth or 32
	local fh = opts.frameHeight or 32
	local g = anim8.newGrid(fw, fh, sheet:getWidth(), sheet:getHeight())

	return {
		idle = anim8.newAnimation(g("1-4", 1), 0.15),
		walk = anim8.newAnimation(g("1-6", 2), 0.10),
		run = anim8.newAnimation(g("1-6", 3), 0.07),
		roll = anim8.newAnimation(g("1-5", 4), 0.07),
		slide = anim8.newAnimation(g("1-4", 5), 0.10),
		attack = anim8.newAnimation(g("1-4", 6), 0.10),
		running_attack = anim8.newAnimation(g("1-5", 7), 0.10),
	}
end
