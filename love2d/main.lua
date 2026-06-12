-- LÖVE port of Dylearn's "3D Pixel Art Grass" Godot demo.
--
-- True 3D, same recipe as the original: a 640x360 render target scaled up
-- with nearest filtering, an orthographic camera, 30k instanced billboard
-- grass quads whose vertex shader does quantised wind sway + character
-- displacement, and toon lighting with scrolling cloud shadows.
-- Scene constants are lifted from Scenes/Demo.tscn.

local lg = love.graphics
local lm = love.math

-- Viewport ------------------------------------------------------------------

local VIEW_W, VIEW_H = 640, 360 -- SubViewport size
local ORTHO_H = 6.085 -- Camera3D size (keep_height)
local ORTHO_W = ORTHO_H * VIEW_W / VIEW_H

-- Camera transform (basis columns + origin from the .tscn)
local CAM_POS = { -14.02, 5.975, 9.92 }
local CAM_X = { 0.582123, 0.0, 0.813101 }
local CAM_Y = { 0.304593, 0.927184, -0.218067 }
local CAM_Z = { -0.753894, 0.374607, 0.539735 }
local CAM_FORWARD = { -CAM_Z[1], -CAM_Z[2], -CAM_Z[3] }

-- DirectionalLight3D basis z (points from surfaces toward the light)
local LIGHT_DIR = { -0.0695626, 0.725375, 0.684831 }
local LIGHT_COLOR = { 1.0, 1.0, 1.0 }

-- World ---------------------------------------------------------------------

local FLOOR_SIZE = 25.0
local GRASS_COUNT = 30000 -- MultiMesh visible_instance_count
local GRASS_FIELD = 12.2 -- grass scatter half-extent
local GRASS_GROUND_PATCH = 0.26

local MAX_CHARACTERS = 16
local CHARACTER_SEND_FRAMERATE = 10.0 -- CharacterManager.gd grass_framerate

-- ShaderGlobals node (cloud shadows)
local CLOUD_PARAMS = {
	cloud_scale = 40.0,
	cloud_world_y = 50.0,
	cloud_speed = -0.04,
	cloud_contrast = 1.845,
	cloud_threshold = 0.3,
	cloud_direction = { 0.0, -1.0 },
	cloud_shadow_min = 0.61,
	cloud_diverge_angle = 20.0,
}

-- Grass ShaderMaterial parameters
local GRASS_PARAMS = {
	albedo1 = { 0.443137, 0.635294, 0.0, 1.0 },
	albedo2 = { 0.556863, 0.678431, 0.211765, 1.0 },
	albedo2_scale = 0.11,
	albedo2_threshold = 0.537,
	albedo3 = { 0.501961, 0.654902, 0.223529, 1.0 },
	albedo3_scale = 0.1,
	albedo3_threshold = 0.471,
	accent_frequency1 = 0.001,
	accent_albedo1 = { 0.603922, 0.717647, 0.0, 1.0 },
	accent_height1 = 0.1,
	accent_scale1 = 1.0,
	accent_probability2 = 0.0001,
	accent_albedo2 = { 0.423529, 0.603922, 0.0, 1.0 },
	accent_height2 = 0.185,
	accent_scale2 = 1.0,
	framerate = 5.0,
	world_sway_angle = 60.0,
	fake_perspective_scale = 0.3,
	wind_noise_threshold = 0.365,
	wind_noise_scale = 0.071,
	wind_noise_speed = 0.025,
	wind_noise_direction = { 0.0, 1.0 },
	noise_diverge_angle = 10.0,
	view_sway_speed = 0.1,
	view_sway_angle = 10.0,
	player_displacement_angle_z = 60.0,
	player_displacement_angle_x = 62.7,
	radius_exponent = 0.9,
	cuts = 3,
	wrap = 0.0,
	steepness = 1.0,
	threshold_gradient_size = 0.255,
}

-- Floor ShaderMaterial parameters
-- Keep floor palette in sync with grass.
local FLOOR_PARAMS = {
	albedo1 = GRASS_PARAMS.albedo1,
	albedo2 = GRASS_PARAMS.albedo2,
	albedo2_scale = GRASS_PARAMS.albedo2_scale,
	albedo2_threshold = GRASS_PARAMS.albedo2_threshold,
	albedo3 = GRASS_PARAMS.albedo3,
	albedo3_scale = GRASS_PARAMS.albedo3_scale,
	albedo3_threshold = GRASS_PARAMS.albedo3_threshold,
	cuts = GRASS_PARAMS.cuts,
	wrap = GRASS_PARAMS.wrap,
	steepness = GRASS_PARAMS.steepness,
	threshold_gradient_size = GRASS_PARAMS.threshold_gradient_size,
}

-- State ---------------------------------------------------------------------

local canvas
local grassShader, grassGroundShader, floorShader, capsuleShader
local grassMesh, grassGroundMesh, floorMesh, capsuleMesh
local grassInstances
local textures = {}
local characters = {}
local time_elapsed = 0.0
local character_send_timer = 0.0
local quantised = true
local debug_noise = false
local displacement_enabled = true
local screenshot_timer = nil

-- Helpers -------------------------------------------------------------------

local function dot3(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function clamp(v, lo, hi)
	return math.min(hi, math.max(lo, v))
end

-- World -> view, column-major (camera basis is orthonormal, so R = B^T)
local function make_view_matrix()
	return {
		CAM_X[1],
		CAM_Y[1],
		CAM_Z[1],
		0.0,
		CAM_X[2],
		CAM_Y[2],
		CAM_Z[2],
		0.0,
		CAM_X[3],
		CAM_Y[3],
		CAM_Z[3],
		0.0,
		-dot3(CAM_X, CAM_POS),
		-dot3(CAM_Y, CAM_POS),
		-dot3(CAM_Z, CAM_POS),
		1.0,
	}
end

local function make_ortho_matrix(width, height, near, far)
	return {
		2.0 / width,
		0.0,
		0.0,
		0.0,
		0.0,
		2.0 / height,
		0.0,
		0.0,
		0.0,
		0.0,
		-2.0 / (far - near),
		0.0,
		0.0,
		0.0,
		-(far + near) / (far - near),
		1.0,
	}
end

local function send_if_present(shader, name, ...)
	if shader:hasUniform(name) then
		shader:send(name, ...)
	end
end

-- Seamless noise textures (the Godot project uses seamless NoiseTexture2D).
-- Tileability comes from sampling 4D noise on a torus; `periods` matches
-- FastNoiseLite frequency * texture size (512) from the .tres files.
local function make_noise_texture(size, periods, seed)
	local radius = periods / (2.0 * math.pi)
	local data = love.image.newImageData(size, size, "r8")
	local tau = 2.0 * math.pi
	data:mapPixel(function(x, y)
		local a = (x / size) * tau
		local b = (y / size) * tau
		local v = lm.noise(
			seed + radius * math.cos(a),
			radius * math.sin(a),
			seed * 0.61803 + radius * math.cos(b),
			radius * math.sin(b)
		)
		return v, v, v, 1.0
	end)
	local img = lg.newImage(data)
	img:setWrap("repeat", "repeat")
	img:setFilter("linear", "linear")
	return img
end

-- Meshes --------------------------------------------------------------------

-- One grass blade: QuadMesh 0.2 x 0.3 centred on its origin, uv.y = 0 at the tip
local function make_grass_mesh()
	local format = {
		{ "VertexPosition", "float", 3 },
		{ "VertexTexCoord", "float", 2 },
	}
	local mesh = lg.newMesh(format, {
		{ -0.1, 0.15, 0.0, 0.0, 0.0 },
		{ 0.1, 0.15, 0.0, 1.0, 0.0 },
		{ 0.1, -0.15, 0.0, 1.0, 1.0 },
		{ -0.1, -0.15, 0.0, 0.0, 1.0 },
	}, "fan", "static")
	mesh:setTexture(textures.grass)
	return mesh
end

local function make_grass_ground_mesh()
	local h = GRASS_GROUND_PATCH * 0.5
	return lg.newMesh({
		{ "VertexPosition", "float", 3 },
		{ "VertexTexCoord", "float", 2 },
	}, {
		{ -h, 0.0, -h, 0.0, 0.0 },
		{ h, 0.0, -h, 1.0, 0.0 },
		{ h, 0.0, h, 1.0, 1.0 },
		{ -h, 0.0, h, 0.0, 1.0 },
	}, "fan", "static")
end

local function make_grass_instances()
	local offsets = {}
	for i = 1, GRASS_COUNT do
		offsets[i] = {
			(lm.random() * 2.0 - 1.0) * GRASS_FIELD,
			0.0,
			(lm.random() * 2.0 - 1.0) * GRASS_FIELD,
		}
	end
	return lg.newMesh({ { "InstanceOffset", "float", 3 } }, offsets, nil, "static")
end

local function attach_grass_instances(mesh, instances)
	mesh:attachAttribute("InstanceOffset", instances, "perinstance")
end

local function rebuild_grass()
	grassMesh = make_grass_mesh()
	grassGroundMesh = make_grass_ground_mesh()
	grassInstances = make_grass_instances()
	attach_grass_instances(grassMesh, grassInstances)
	attach_grass_instances(grassGroundMesh, grassInstances)
end

local function make_floor_mesh()
	local h = FLOOR_SIZE * 0.5
	return lg.newMesh({ { "VertexPosition", "float", 3 } }, {
		{ -h, 0.0, -h },
		{ h, 0.0, -h },
		{ h, 0.0, h },
		{ -h, 0.0, h },
	}, "fan", "static")
end

-- CapsuleMesh radius 0.3, height 1.5 (two hemispheres + cylinder), local y in [-0.75, 0.75]
local function make_capsule_mesh(radius, height, segments, rings)
	local cyl_half = height * 0.5 - radius
	local verts, indices = {}, {}
	local rows = {}
	for i = 0, rings * 2 do
		local phi = -math.pi * 0.5 + (i / (rings * 2)) * math.pi
		local y_off = (i <= rings) and -cyl_half or cyl_half
		rows[#rows + 1] = { phi = phi, y_off = y_off }
		if i == rings then -- duplicate the equator row for the cylinder wall
			rows[#rows + 1] = { phi = phi, y_off = cyl_half }
		end
	end
	for _, row in ipairs(rows) do
		local cy = math.sin(row.phi)
		local cr = math.cos(row.phi)
		for s = 0, segments do
			local theta = (s / segments) * 2.0 * math.pi
			local nx, ny, nz = cr * math.cos(theta), cy, cr * math.sin(theta)
			verts[#verts + 1] = {
				nx * radius,
				ny * radius + row.y_off,
				nz * radius,
				nx,
				ny,
				nz,
			}
		end
	end
	local stride = segments + 1
	for r = 0, #rows - 2 do
		for s = 0, segments - 1 do
			local a = r * stride + s + 1
			local b = a + 1
			local c = a + stride
			local d = c + 1
			indices[#indices + 1] = a
			indices[#indices + 1] = c
			indices[#indices + 1] = b
			indices[#indices + 1] = b
			indices[#indices + 1] = c
			indices[#indices + 1] = d
		end
	end
	local mesh = lg.newMesh({
		{ "VertexPosition", "float", 3 },
		{ "VertexNormal", "float", 3 },
	}, verts, "triangles", "static")
	mesh:setVertexMap(indices)
	return mesh
end

-- Characters (RandomPositionCharacter.gd) ------------------------------------

local function ortho_ray_origin(u, v)
	-- u: 0..1 across the screen, v: 0..1 down the screen
	local ox = (u - 0.5) * ORTHO_W
	local oy = (0.5 - v) * ORTHO_H
	return {
		CAM_POS[1] + CAM_X[1] * ox + CAM_Y[1] * oy,
		CAM_POS[2] + CAM_X[2] * ox + CAM_Y[2] * oy,
		CAM_POS[3] + CAM_X[3] * ox + CAM_Y[3] * oy,
	}
end

-- Random point on the ground in the bottom half of the camera's view
local function random_visible_ground_point(ch)
	for _ = 1, 10 do
		local origin = ortho_ray_origin(lm.random(), 0.5 + 0.5 * lm.random())
		local dir = CAM_FORWARD
		if math.abs(dir[2]) > 0.001 then
			local t = -origin[2] / dir[2]
			if t > 0.0 then
				return { origin[1] + dir[1] * t, 0.0, origin[3] + dir[3] * t }
			end
		end
	end
	return { ch.pos[1], ch.pos[2], ch.pos[3] }
end

local function spawn_characters()
	-- Positions are the Characters node children resolved to world space
	characters = {
		{
			pos = { -2.22791, 0.0, 5.80089 },
			speed = 2.0,
			accel = 5.0,
			size = 0.86,
			mesh_scale = { 2.0, 1.0, 2.0 },
			mesh_y = 0.75,
		},
		{
			pos = { -5.84467, 0.0, 5.51433 },
			speed = 2.5,
			accel = 5.0,
			size = 0.53,
			mesh_scale = { 1.0, 1.0, 1.0 },
			mesh_y = 0.75,
		},
		{
			pos = { -2.62366, 0.0, 8.07181 },
			speed = 3.0,
			accel = 5.0,
			size = 0.38,
			mesh_scale = { 0.5, 0.5, 0.5 },
			mesh_y = 0.4,
		},
	}
	for _, ch in ipairs(characters) do
		ch.vel = { 0.0, 0.0, 0.0 }
		ch.waiting = false
		ch.wait_timer = 0.0
		ch.wait_time = 0.1
		ch.target = random_visible_ground_point(ch)
	end
end

local function move_toward3(vel, target, max_delta)
	local dx = target[1] - vel[1]
	local dy = target[2] - vel[2]
	local dz = target[3] - vel[3]
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len <= max_delta or len < 1e-8 then
		return { target[1], target[2], target[3] }
	end
	local k = max_delta / len
	return { vel[1] + dx * k, vel[2] + dy * k, vel[3] + dz * k }
end

local function update_character(ch, dt)
	if ch.waiting then
		ch.wait_timer = ch.wait_timer - dt
		if ch.wait_timer <= 0.0 then
			ch.waiting = false
			ch.target = random_visible_ground_point(ch)
		end
		return
	end

	local tx = ch.target[1] - ch.pos[1]
	local tz = ch.target[3] - ch.pos[3]
	local distance = math.sqrt(tx * tx + tz * tz)
	if distance < 0.1 then
		ch.vel = { 0.0, 0.0, 0.0 }
		ch.waiting = true
		ch.wait_timer = ch.wait_time
		return
	end

	local slow_radius = 2.0
	local speed_scale = clamp(distance / slow_radius, 0.0, 1.0)
	local target_vel = {
		tx / distance * ch.speed * speed_scale,
		0.0,
		tz / distance * ch.speed * speed_scale,
	}
	ch.vel = move_toward3(ch.vel, target_vel, ch.accel * dt)
	ch.pos[1] = ch.pos[1] + ch.vel[1] * dt
	ch.pos[3] = ch.pos[3] + ch.vel[3] * dt
end

-- CharacterManager.gd: push character positions to the grass shader at 10 fps
local function send_character_positions()
	local packed = {}
	for i = 1, MAX_CHARACTERS do
		local ch = characters[i]
		if ch and displacement_enabled then
			packed[i] = { ch.pos[1], ch.pos[2], ch.pos[3], ch.size }
		else
			packed[i] = { 0.0, 0.0, 0.0, 0.0 }
		end
	end
	grassShader:send("character_positions", unpack(packed))
end

-- Setup ----------------------------------------------------------------------

local function send_cloud_params(shader)
	shader:send("cloud_noise", textures.cloud_noise)
	shader:send("light_direction", LIGHT_DIR)
	for name, value in pairs(CLOUD_PARAMS) do
		shader:send(name, value)
	end
end

local function send_static_uniforms()
	local view = make_view_matrix()
	local proj = make_ortho_matrix(ORTHO_W, ORTHO_H, 0.05, 200.0)

	grassShader:send("u_view", "column", view)
	grassShader:send("u_proj", "column", proj)
	grassShader:send("camera_forward_world", CAM_FORWARD)
	grassShader:send("wind_noise", textures.wind_noise)
	grassShader:send("albedo2_noise", textures.albedo2_noise)
	grassShader:send("albedo3_noise", textures.albedo3_noise)
	grassShader:send("accent_texture2", textures.accent)
	grassShader:send("u_light_color", LIGHT_COLOR)
	-- The billboarded blade normal faces the camera, so NdotL is constant
	grassShader:send("u_ndotl", dot3(CAM_Z, LIGHT_DIR))
	grassShader:send("quantised", quantised)
	grassShader:send("world_space_sway", true)
	grassShader:send("view_space_sway", true)
	grassShader:send("character_displacement", true)
	grassShader:send("debug_noise", debug_noise)
	for name, value in pairs(GRASS_PARAMS) do
		send_if_present(grassShader, name, value)
	end
	send_cloud_params(grassShader)

	grassGroundShader:send("u_view", "column", view)
	grassGroundShader:send("u_proj", "column", proj)
	grassGroundShader:send("albedo2_noise", textures.albedo2_noise)
	grassGroundShader:send("albedo3_noise", textures.albedo3_noise)
	grassGroundShader:send("u_light_color", LIGHT_COLOR)
	grassGroundShader:send("u_ndotl", dot3(CAM_Z, LIGHT_DIR))
	for name, value in pairs(GRASS_PARAMS) do
		send_if_present(grassGroundShader, name, value)
	end
	send_cloud_params(grassGroundShader)

	floorShader:send("u_view", "column", view)
	floorShader:send("u_proj", "column", proj)
	floorShader:send("albedo2_noise", textures.albedo2_noise)
	floorShader:send("albedo3_noise", textures.albedo3_noise)
	floorShader:send("u_light_color", LIGHT_COLOR)
	floorShader:send("u_ndotl", dot3(CAM_Z, LIGHT_DIR))
	for name, value in pairs(FLOOR_PARAMS) do
		send_if_present(floorShader, name, value)
	end
	send_cloud_params(floorShader)

	capsuleShader:send("u_view", "column", view)
	capsuleShader:send("u_proj", "column", proj)
	capsuleShader:send("light_direction", LIGHT_DIR)
	capsuleShader:send("u_albedo", { 1.0, 1.0, 1.0 })
	capsuleShader:send("u_alpha", 0.3) -- Godot transparency = 0.7
end

function love.errorhandler(msg)
	print("ERROR: " .. tostring(msg) .. "\n" .. debug.traceback())
	io.stdout:flush()
	local f = io.open("/tmp/love_error.txt", "w")
	if f then
		f:write(tostring(msg) .. "\n" .. debug.traceback())
		f:close()
	end
	os.exit(1)
end

function love.load(args)
	for _, a in ipairs(args or {}) do
		if a == "--shot" then
			screenshot_timer = 2.5
		end
	end

	lg.setDefaultFilter("nearest", "nearest")

	textures.grass = lg.newImage("assets/grassleaf.png")
	textures.accent = lg.newImage("assets/accentleaf.png")
	-- periods = FastNoiseLite frequency * 512 (NoiseTexture2D default size)
	textures.wind_noise = make_noise_texture(256, 512 * 0.01, 4.7)
	textures.albedo2_noise = make_noise_texture(256, 512 * 0.0046, 17.3)
	textures.albedo3_noise = make_noise_texture(256, 512 * 0.0052, 31.7)
	textures.cloud_noise = make_noise_texture(256, 512 * 0.01, 47.9)

	grassShader = lg.newShader("shaders/grass.glsl")
	grassGroundShader = lg.newShader("shaders/grass_ground.glsl")
	floorShader = lg.newShader("shaders/floor.glsl")
	capsuleShader = lg.newShader("shaders/capsule.glsl")

	canvas = lg.newCanvas(VIEW_W, VIEW_H)
	canvas:setFilter("nearest", "nearest")

	rebuild_grass()
	floorMesh = make_floor_mesh()
	capsuleMesh = make_capsule_mesh(0.3, 1.5, 16, 6)

	spawn_characters()
	send_static_uniforms()
	send_character_positions()
end

function love.update(dt)
	time_elapsed = time_elapsed + dt

	for _, ch in ipairs(characters) do
		update_character(ch, dt)
	end

	character_send_timer = character_send_timer + dt
	local frametime = 1.0 / CHARACTER_SEND_FRAMERATE
	if character_send_timer >= frametime then
		character_send_timer = character_send_timer - frametime
		send_character_positions()
	end

	if screenshot_timer then
		screenshot_timer = screenshot_timer - dt
		if screenshot_timer <= 0.0 then
			screenshot_timer = nil
			lg.captureScreenshot(function(imagedata)
				imagedata:encode("png", "shot.png")
				love.event.quit()
			end)
		end
	end
end

function love.keypressed(key)
	if key == "escape" then
		love.event.quit()
	elseif key == "space" then
		quantised = not quantised
		grassShader:send("quantised", quantised)
	elseif key == "n" then
		debug_noise = not debug_noise
		grassShader:send("debug_noise", debug_noise)
	elseif key == "c" then
		displacement_enabled = not displacement_enabled
		send_character_positions()
	elseif key == "r" then
		rebuild_grass()
	end
end

function love.draw()
	lg.setCanvas({ canvas, depth = true })
	lg.clear(0.35, 0.47, 0.55, 1.0, true, true)
	lg.setDepthMode("lequal", true)
	lg.setMeshCullMode("none")
	lg.setColor(1, 1, 1, 1)

	floorShader:send("u_time", time_elapsed)
	lg.setShader(floorShader)
	lg.draw(floorMesh)

	grassGroundShader:send("u_time", time_elapsed)
	lg.setDepthMode("lequal", false)
	lg.setShader(grassGroundShader)
	lg.drawInstanced(grassGroundMesh, GRASS_COUNT)

	grassShader:send("u_time", time_elapsed)
	lg.setDepthMode("lequal", true)
	lg.setShader(grassShader)
	lg.drawInstanced(grassMesh, GRASS_COUNT)

	-- Translucent capsules: depth-tested but not depth-written, back to front
	lg.setDepthMode("lequal", false)
	lg.setShader(capsuleShader)
	local order = { unpack(characters) }
	table.sort(order, function(a, b)
		local da = (a.pos[1] - CAM_POS[1]) * CAM_FORWARD[1] + (a.pos[3] - CAM_POS[3]) * CAM_FORWARD[3]
		local db = (b.pos[1] - CAM_POS[1]) * CAM_FORWARD[1] + (b.pos[3] - CAM_POS[3]) * CAM_FORWARD[3]
		return da > db
	end)
	for _, ch in ipairs(order) do
		capsuleShader:send("u_model_scale", ch.mesh_scale)
		capsuleShader:send("u_model_offset", { ch.pos[1], ch.pos[2] + ch.mesh_y, ch.pos[3] })
		lg.draw(capsuleMesh)
	end

	lg.setShader()
	lg.setDepthMode()
	lg.setCanvas()

	-- Blit the 3D canvas at an integer scale; gl_Position output needs a y-flip
	local w, h = lg.getDimensions()
	local scale = math.max(1, math.floor(math.min(w / VIEW_W, h / VIEW_H)))
	local ox = math.floor((w - VIEW_W * scale) * 0.5)
	local oy = math.floor((h - VIEW_H * scale) * 0.5)
	lg.setColor(1, 1, 1, 1)
	lg.draw(canvas, ox, oy + VIEW_H * scale, 0, scale, -scale)

	lg.setColor(1, 1, 1, 0.85)
	lg.print(
		"Space: stepped wind ("
			.. tostring(quantised)
			.. ")  |  C: displacement ("
			.. tostring(displacement_enabled)
			.. ")  |  N: wind debug  |  R: rescatter  |  Esc: quit  |  FPS: "
			.. love.timer.getFPS(),
		12,
		12
	)
	lg.print(love.timer.getFPS() .. " fps, " .. GRASS_COUNT .. " blades", 12, 30)
end
