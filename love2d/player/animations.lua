-- anim8 animation set for the player action host.
--
-- The spritesheet (assets/spritesheet/) is an 8-directional Mixamo character on
-- a clean 64px grid: rows 1-8 are the walk cycle (N, NE, E, SE, S, SW, W, NW;
-- see spritesheet.manifest.json), rows 9-16 are a T-pose take we don't use.
--
-- The action host/FSM only know base actions (idle/walk/run/...), so each entry
-- below is a DirAnim: 8 anim8 animations sharing one `facing` ref (the Player
-- updates it from movement). It exposes just the slice of the anim8 interface
-- the host and Player call — update(dt), gotoFrame(n), draw(image, ...).
local anim8 = require("lib.anim8")

local DIRS = { "n", "ne", "e", "se", "s", "sw", "w", "nw" }
local WALK_ROW = { n = 1, ne = 2, e = 3, se = 4, s = 5, sw = 6, w = 7, nw = 8 }

local DirAnim = {}
DirAnim.__index = DirAnim

function DirAnim.new(byDir, facing)
	return setmetatable({ byDir = byDir, facing = facing }, DirAnim)
end

function DirAnim:_current()
	return self.byDir[self.facing.dir] or self.byDir.s
end

function DirAnim:gotoFrame(n)
	for _, a in pairs(self.byDir) do
		a:gotoFrame(n)
	end
end

function DirAnim:update(dt)
	self:_current():update(dt)
end

function DirAnim:draw(image, ...)
	self:_current():draw(image, ...)
end

return function(sheet, opts)
	opts = opts or {}
	local fw = opts.frameWidth or 64
	local fh = opts.frameHeight or 64
	local facing = opts.facing or { dir = "s" }
	local grid = anim8.newGrid(fw, fh, sheet:getWidth(), sheet:getHeight())

	-- One DirAnim from a per-direction (columns, frame duration) spec.
	local function directional(cols, duration)
		local byDir = {}
		for _, d in ipairs(DIRS) do
			byDir[d] = anim8.newAnimation(grid(cols, WALK_ROW[d]), duration)
		end
		return DirAnim.new(byDir, facing)
	end

	local walk = directional("1-9", 1 / 7) -- manifest fps = 7
	local run = directional("1-9", 1 / 12)
	local idle = directional(1, 1) -- frame 1 only: a standing pose per direction

	return {
		idle = idle,
		walk = walk,
		run = run,
		-- The sheet has no roll/slide/attack art; reuse locomotion so the action
		-- host never indexes a missing animation.
		roll = walk,
		slide = run,
		attack = walk,
		running_attack = run,
	}
end
