-- Reusable flat elliptical contact shadow for ground entities.
-- Configure once with Shadow.new{...}, then call shadow:draw(x, y) each frame
-- at the entity's base (window-space pixels).
local Shadow = {}
Shadow.__index = Shadow

function Shadow.new(opts)
	opts = opts or {}
	return setmetatable({
		radius = opts.radius or 20, -- horizontal radius, pixels
		squash = opts.squash or 0.45, -- ry/rx, ground foreshortening
		alpha = opts.alpha or 0.55,
		color = opts.color or { 0, 0, 0 },
	}, Shadow)
end

-- Draw the shadow centred at (x, y).
function Shadow:draw(x, y)
	local c = self.color
	love.graphics.setColor(c[1], c[2], c[3], self.alpha)
	love.graphics.ellipse("fill", x, y, self.radius, self.radius * self.squash)
	love.graphics.setColor(1, 1, 1, 1)
end

return Shadow
