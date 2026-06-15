-- Player: wires baton (input) + anim8 (animations) into the existing
-- action host / FSM / controller. Construct one in love.load, then call
-- player:update(dt) and player:draw().
local PlayerActionHost = require("player.action_host")
local PlayerFsm = require("player.fsm")
local PlayerController = require("player.controller")
local buildInput = require("player.input")
local buildAnimations = require("player.animations")
local Shadow = require("shadow")

local FRAME_W, FRAME_H = 32, 32
local SHEET_COLS, SHEET_ROWS = 6, 7 -- enough rows/cols for animations.lua

local Player = {}
Player.__index = Player

-- A generated stand-in sheet so the player is visible before real art exists.
-- One hue per animation row, brighter toward later frames, with a 1px border.
local function makePlaceholderSheet()
	local w, h = FRAME_W * SHEET_COLS, FRAME_H * SHEET_ROWS
	local data = love.image.newImageData(w, h)
	data:mapPixel(function(x, y)
		local lx, ly = x % FRAME_W, y % FRAME_H
		if lx < 1 or ly < 1 or lx >= FRAME_W - 1 or ly >= FRAME_H - 1 then
			return 0, 0, 0, 1
		end
		local hue = math.floor(y / FRAME_H) / SHEET_ROWS
		local shade = 0.45 + 0.55 * (math.floor(x / FRAME_W) / SHEET_COLS)
		local r = (0.5 + 0.5 * math.sin(hue * 6.28318)) * shade
		local g = (0.5 + 0.5 * math.sin(hue * 6.28318 + 2.094)) * shade
		local b = (0.5 + 0.5 * math.sin(hue * 6.28318 + 4.188)) * shade
		return r, g, b, 1
	end)
	local img = love.graphics.newImage(data)
	img:setFilter("nearest", "nearest")
	return img
end

local function loadSheet(path)
	if path and love.filesystem.getInfo(path) then
		local sheet = love.graphics.newImage(path)
		sheet:setFilter("nearest", "nearest")
		return sheet
	end
	return makePlaceholderSheet()
end

function Player.new(opts)
	opts = opts or {}

	local sheet = loadSheet(opts.sheet)
	local frameW = opts.frameWidth or FRAME_W
	local frameH = opts.frameHeight or FRAME_H
	local scale = opts.scale or 2
	local animations = buildAnimations(sheet, {
		frameWidth = frameW,
		frameHeight = frameH,
	})
	local host = PlayerActionHost:new(animations)
	local input = buildInput()
	local fsm = PlayerFsm.create(host)
	local controller = PlayerController:new(host, input, fsm)
	host:setController(controller) -- lets timed actions report back when done

	local shadow = Shadow.new({
		radius = opts.shadowRadius or (frameW * scale) * 0.35,
		squash = opts.shadowSquash,
		alpha = opts.shadowAlpha or 0.1,
	})

	return setmetatable({
		sheet = sheet,
		host = host,
		input = input,
		fsm = fsm,
		controller = controller,
		x = opts.x or 100,
		y = opts.y or 100,
		scale = scale,
		frameW = frameW,
		frameH = frameH,
		walkSpeed = opts.walkSpeed or 120, -- pixels/sec
		runSpeed = opts.runSpeed or 240,
		grassRadius = opts.grassRadius or 0.5, -- world units the grass bends within
		shadow = shadow,
	}, Player)
end

-- Window-space position of the sprite's base (bottom-centre / "feet").
-- main.lua inverse-projects this to a world ground point for grass displacement.
function Player:footPosition()
	return self.x + (self.frameW * self.scale) * 0.5, self.y + self.frameH * self.scale
end

function Player:update(dt)
	self.controller:update(dt) -- also calls input:update(dt) internally
	self.host:update(dt) -- advances anim8 + the action timer

	-- The controller/FSM only choose the animation; they never move the
	-- sprite. Integrate position here from the same baton "move" pair.
	local mx, my = self.input:get("move")
	local speed = self.input:down("run") and self.runSpeed or self.walkSpeed
	self.x = self.x + (mx or 0) * speed * dt
	self.y = self.y + (my or 0) * speed * dt
end

function Player:draw()
	-- Contact shadow centred on the grass-displacement point (under the feet).
	self.shadow:draw(self:footPosition())

	local anim = self.host.animations[self.host.currentAnimation]
	if not anim then
		return
	end
	anim:draw(self.sheet, self.x, self.y, 0, self.scale, self.scale)
end

return Player
