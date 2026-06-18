-- LÖVE port of Dylearn's "3D Pixel Art Grass" Godot demo.
--
-- True 3D, same recipe as the original: a 640x360 render target scaled up
-- with nearest filtering, an orthographic camera, 30k instanced billboard
-- grass quads whose vertex shader does quantised wind sway + character
-- displacement, and toon lighting with scrolling cloud shadows.
-- Scene constants are lifted from Scenes/Demo.tscn.

local lg = love.graphics
local lm = love.math

local Player = require("player")

-- Viewport ------------------------------------------------------------------

-- Internal render resolution (mutable): the 3D scene renders into a canvas this
-- size, then gets upscaled to the window on blit. apply_quality() lowers it for
-- cheaper tiers; it stays 16:9 so the orthographic projection is unaffected.
local VIEW_W, VIEW_H = 640, 360
local ASPECT = 16 / 9
local ORTHO_H = 6.085 -- Camera3D size (keep_height)
local ORTHO_W = ORTHO_H * ASPECT

-- Camera transform (basis columns + origin from the .tscn)
local CAM_POS = { -14.02, 5.975, 9.92 }
local CAM_X = { 0.582123, 0.0, 0.813101 }
local CAM_Y = { 0.304593, 0.927184, -0.218067 }
local CAM_Z = { -0.753894, 0.374607, 0.539735 }
local CAM_FORWARD = { -CAM_Z[1], -CAM_Z[2], -CAM_Z[3] }

-- DirectionalLight3D basis z from the source scene. The time-of-day cycle uses
-- it as the 09:00 anchor so the demo opens close to the original lighting.
local SOURCE_LIGHT_DIR = { -0.0695626, 0.725375, 0.684831 }
local LIGHT_ENERGY = 1.0 -- DirectionalLight3D.energy; scales the lit colour
local DAY_CYCLE_SECONDS = 96.0
local DAY_START_HOUR = 9.0
local MIN_LIGHT_ELEVATION = math.rad(7.0)
local LIGHT_TEMP_SUNRISE = 2800.0
local LIGHT_TEMP_NOON = 6500.0
local LIGHT_TEMP_NIGHT = 9000.0
local SKY_DAY = { 0.35, 0.47, 0.55 }
local SKY_GOLDEN = { 0.74, 0.39, 0.24 }
local SKY_NIGHT = { 0.08, 0.10, 0.18 }
local light_anchor_azimuth = 0.0
local light_state = {
	direction = { SOURCE_LIGHT_DIR[1], SOURCE_LIGHT_DIR[2], SOURCE_LIGHT_DIR[3] },
	color = { 1.0, 1.0, 1.0 },
	energy = LIGHT_ENERGY,
	sky = { SKY_DAY[1], SKY_DAY[2], SKY_DAY[3] },
	temperature = LIGHT_TEMP_NOON,
}

-- World ---------------------------------------------------------------------

local FLOOR_SIZE = 25.0

-- Grass density presets. GRASS_COUNT is the live (mutable) value; love.load picks
-- a tier from the device and apply_quality() swaps it at runtime. 30000 is the
-- original MultiMesh visible_instance_count.
local GRASS_QUALITY = {
	-- blades   = scatter density
	-- render_h = internal render height (16:9, upscaled to the window). Lower is
	--            cheaper: the grass shader is fragment-heavy, so fewer pixels helps
	--            far more than fewer blades on a weak GPU.
	low = { blades = 1000, render_h = 72 },
	medium = { blades = 5000, render_h = 144 },
	high = { blades = 15000, render_h = 216 },
}
local GRASS_QUALITY_ORDER = { "low", "medium", "high" }
local GRASS_COUNT = GRASS_QUALITY.high.blades
local GRASS_FIELD = 12.2 -- grass scatter half-extent
local GRASS_GROUND_PATCH = 0.26

local MAX_CHARACTERS = 16
local CHARACTER_SEND_FRAMERATE = 10.0 -- CharacterManager.gd grass_framerate

-- ShaderGlobals node (cloud shadows)
local CLOUD_PARAMS = {
	cloud_scale = 40.0,
	cloud_world_y = 50.0,
	cloud_speed = -0.02,
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
	-- player_displacement_angle_z = 60.0,
	-- player_displacement_angle_x = 62.7,
	player_displacement_angle_z = 160.0,
	player_displacement_angle_x = 162.7,
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
local grassShader, grassGroundShader, floorShader, capsuleShader, playerShader, gradeShader
local grassMesh, grassGroundMesh, floorMesh, capsuleMesh
local grassInstances
local instancing -- vertex attribute instancing supported? (false on the Pi)
local quality = "high" -- current grass density preset
local textures = {}
local characters = {}
local time_elapsed = 0.0
local day_hour = DAY_START_HOUR
local character_send_timer = 0.0
local quantised = true
local debug_noise = false
local displacement_enabled = true
local day_cycle_enabled = true
local saturation = 1.0 -- scene colour saturation (lower = washed-out / bad weather)
local screenshot_timer = nil
local player

-- Helpers -------------------------------------------------------------------

local function dot3(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function clamp(v, lo, hi)
	return math.min(hi, math.max(lo, v))
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smoothstep(edge0, edge1, x)
	if edge0 == edge1 then
		return x < edge0 and 0.0 or 1.0
	end
	local t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
end

local function mix3(a, b, t)
	return {
		lerp(a[1], b[1], t),
		lerp(a[2], b[2], t),
		lerp(a[3], b[3], t),
	}
end

local function atan2(y, x)
	if x > 0.0 then
		return math.atan(y / x)
	elseif x < 0.0 and y >= 0.0 then
		return math.atan(y / x) + math.pi
	elseif x < 0.0 then
		return math.atan(y / x) - math.pi
	elseif y > 0.0 then
		return math.pi * 0.5
	elseif y < 0.0 then
		return -math.pi * 0.5
	end
	return 0.0
end

local function kelvin_to_rgb(kelvin)
	local temp = clamp(kelvin, 1000.0, 40000.0) / 100.0
	local r, g, b

	if temp <= 66.0 then
		r = 1.0
		g = clamp((99.4708025861 * math.log(temp) - 161.1195681661) / 255.0, 0.0, 1.0)
	else
		r = clamp((329.698727446 * ((temp - 60.0) ^ -0.1332047592)) / 255.0, 0.0, 1.0)
		g = clamp((288.1221695283 * ((temp - 60.0) ^ -0.0755148492)) / 255.0, 0.0, 1.0)
	end

	if temp >= 66.0 then
		b = 1.0
	elseif temp <= 19.0 then
		b = 0.0
	else
		b = clamp((138.5177312231 * math.log(temp - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0)
	end

	return { r, g, b }
end

light_anchor_azimuth = atan2(SOURCE_LIGHT_DIR[1], SOURCE_LIGHT_DIR[3]) - math.pi * 0.25

local function update_lighting_state()
	-- 06:00 sunrise, 12:00 noon, 18:00 sunset. Negative height is night, but
	-- the rendered direction stays barely above the horizon for stable clouds.
	local solar_angle = ((day_hour - 6.0) / 12.0) * math.pi
	local raw_height = math.sin(solar_angle)
	local daylight = clamp(raw_height, 0.0, 1.0)
	local min_y = math.sin(MIN_LIGHT_ELEVATION)
	local visual_y = math.max(min_y, raw_height)
	local elevation = math.asin(clamp(visual_y, min_y, 1.0))
	local azimuth = light_anchor_azimuth + solar_angle
	local horizontal = math.cos(elevation)

	local horizon_warmth = 1.0 - smoothstep(0.08, 0.78, daylight)
	local day_blend = smoothstep(-0.05, 0.18, raw_height)
	local kelvin = lerp(LIGHT_TEMP_NOON, LIGHT_TEMP_SUNRISE, horizon_warmth)
	local color = mix3(kelvin_to_rgb(LIGHT_TEMP_NIGHT), kelvin_to_rgb(kelvin), day_blend)
	local power = smoothstep(-0.06, 0.82, raw_height)
	local sky = mix3(SKY_NIGHT, SKY_DAY, smoothstep(-0.12, 0.55, raw_height))
	local golden_sky = horizon_warmth * smoothstep(-0.08, 0.16, raw_height) * (1.0 - smoothstep(0.35, 0.85, raw_height))

	light_state.direction = {
		horizontal * math.sin(azimuth),
		math.sin(elevation),
		horizontal * math.cos(azimuth),
	}
	light_state.color = color
	light_state.energy = LIGHT_ENERGY * lerp(0.18, 1.08, power)
	light_state.sky = mix3(sky, SKY_GOLDEN, golden_sky * 0.55)
	light_state.temperature = lerp(LIGHT_TEMP_NIGHT, kelvin, day_blend)
end

local function format_hour(hour)
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60.0 + 0.5)
	if m >= 60 then
		h = (h + 1) % 24
		m = 0
	end
	return string.format("%02d:%02d", h, m)
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

local GRASS_VERTEX_FORMAT = {
	{ "VertexPosition", "float", 3 },
	{ "VertexTexCoord", "float", 2 },
}

-- Baked format: the per-blade origin travels per-vertex for the non-instanced
-- fallback (see rebuild_grass), so the shader's InstanceOffset attribute is fed
-- identically whether it arrives per-instance or per-vertex.
local GRASS_VERTEX_FORMAT_BAKED = {
	{ "VertexPosition", "float", 3 },
	{ "VertexTexCoord", "float", 2 },
	{ "InstanceOffset", "float", 3 },
}

-- One grass blade: QuadMesh 0.2 x 0.3 centred on its origin, uv.y = 0 at the tip
local GRASS_BLADE_VERTS = {
	{ -0.1, 0.15, 0.0, 0.0, 0.0 },
	{ 0.1, 0.15, 0.0, 1.0, 0.0 },
	{ 0.1, -0.15, 0.0, 1.0, 1.0 },
	{ -0.1, -0.15, 0.0, 0.0, 1.0 },
}

local function grass_ground_verts()
	local h = GRASS_GROUND_PATCH * 0.5
	return {
		{ -h, 0.0, -h, 0.0, 0.0 },
		{ h, 0.0, -h, 1.0, 0.0 },
		{ h, 0.0, h, 1.0, 1.0 },
		{ -h, 0.0, h, 0.0, 1.0 },
	}
end

local function make_grass_mesh()
	local mesh = lg.newMesh(GRASS_VERTEX_FORMAT, GRASS_BLADE_VERTS, "fan", "static")
	mesh:setTexture(textures.grass)
	return mesh
end

local function make_grass_ground_mesh()
	return lg.newMesh(GRASS_VERTEX_FORMAT, grass_ground_verts(), "fan", "static")
end

-- Scatter the blades over the field; shared by both render paths.
local function make_grass_offsets()
	local offsets = {}
	for i = 1, GRASS_COUNT do
		offsets[i] = {
			(lm.random() * 2.0 - 1.0) * GRASS_FIELD,
			0.0,
			(lm.random() * 2.0 - 1.0) * GRASS_FIELD,
		}
	end
	return offsets
end

local function attach_grass_instances(mesh, instances)
	mesh:attachAttribute("InstanceOffset", instances, "perinstance")
end

-- Fallback for GPUs without vertex instancing (the Pi's GL ES driver): bake
-- every blade into one big mesh, replicating its origin into a per-vertex
-- InstanceOffset attribute. One lg.draw replaces drawInstanced; shaders unchanged.
local function make_baked_grass_mesh(baseVerts, offsets, texture)
	local n = #baseVerts
	local verts = {}
	local indices = {}
	local base = 0
	for i = 1, #offsets do
		local off = offsets[i]
		for j = 1, n do
			local bv = baseVerts[j]
			verts[#verts + 1] = { bv[1], bv[2], bv[3], bv[4], bv[5], off[1], off[2], off[3] }
		end
		-- triangle-fan over the quad: (1,2,3), (1,3,4), ...
		for k = 2, n - 1 do
			indices[#indices + 1] = base + 1
			indices[#indices + 1] = base + k
			indices[#indices + 1] = base + k + 1
		end
		base = base + n
	end
	local mesh = lg.newMesh(GRASS_VERTEX_FORMAT_BAKED, verts, "triangles", "static")
	mesh:setVertexMap(indices)
	if texture then
		mesh:setTexture(texture)
	end
	return mesh
end

local function rebuild_grass()
	if instancing then
		grassMesh = make_grass_mesh()
		grassGroundMesh = make_grass_ground_mesh()
		grassInstances = lg.newMesh({ { "InstanceOffset", "float", 3 } }, make_grass_offsets(), nil, "static")
		attach_grass_instances(grassMesh, grassInstances)
		attach_grass_instances(grassGroundMesh, grassInstances)
	else
		local offsets = make_grass_offsets()
		grassMesh = make_baked_grass_mesh(GRASS_BLADE_VERTS, offsets, textures.grass)
		grassGroundMesh = make_baked_grass_mesh(grass_ground_verts(), offsets, nil)
	end
end

local function draw_grass(mesh)
	if instancing then
		lg.drawInstanced(mesh, GRASS_COUNT)
	else
		lg.draw(mesh)
	end
end

-- Pick a starting quality from what we can learn about the device. The clearest
-- signal we have is instancing support: its absence means an embedded/old GPU
-- (e.g. the Raspberry Pi), which also runs the heavier non-instanced path, so we
-- drop to low. Otherwise grade by CPU core count as a rough capability proxy.
-- (LÖVE 11.5 exposes no direct GPU tier/VRAM, so this is intentionally coarse.)
local function detect_quality()
	if not instancing then
		return "low"
	end
	local cores = love.system.getProcessorCount() or 4
	if cores >= 8 then
		return "high"
	elseif cores >= 4 then
		return "medium"
	end
	return "low"
end

-- Switch density and rebuild the grass meshes. Cheap on the instanced path; on
-- the baked (Pi) path this re-bakes the mesh, so expect a brief hitch.
local function apply_quality(name)
	if not GRASS_QUALITY[name] then
		name = "high"
	end
	quality = name
	local q = GRASS_QUALITY[name]
	GRASS_COUNT = q.blades

	-- Resize the internal render target. Rendering the 3D scene at a low
	-- resolution and upscaling with nearest filtering keeps the pixel-art look
	-- while cutting fragment-shader cost (the real bottleneck on the Pi).
	VIEW_H = q.render_h
	VIEW_W = math.floor(VIEW_H * ASPECT + 0.5)
	canvas = lg.newCanvas(VIEW_W, VIEW_H)
	canvas:setFilter("nearest", "nearest")

	rebuild_grass()
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

-- Window pixel -> world ground point (inverse of the canvas blit + ortho
-- camera). Used to plant the 2D player sprite's feet into the 3D grass.
local function ground_under_screen(px, py)
	local w, h = lg.getDimensions()
	local scale = math.max(1, math.floor(math.min(w / VIEW_W, h / VIEW_H)))
	local sx = math.floor((w - VIEW_W * scale) * 0.5)
	local sy = math.floor((h - VIEW_H * scale) * 0.5)
	local u = (px - sx) / (VIEW_W * scale)
	local v = (py - sy) / (VIEW_H * scale)
	local origin = ortho_ray_origin(u, v)
	local dir = CAM_FORWARD
	if math.abs(dir[2]) < 1e-6 then
		return nil
	end
	local t = -origin[2] / dir[2]
	if t <= 0.0 then
		return nil
	end
	return { origin[1] + dir[1] * t, 0.0, origin[3] + dir[3] * t }
end

-- Signed distance along the camera forward axis (ground plane). Bigger = closer
-- to the camera; used to depth-sort the translucent capsules and the player.
local function camera_depth(x, z)
	return (x - CAM_POS[1]) * CAM_FORWARD[1] + (z - CAM_POS[3]) * CAM_FORWARD[3]
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

	-- Plant the player's feet into the grass: slot its ground point after the
	-- NPCs (3 used, 16 available) so blades bend under the sprite's base.
	if player and displacement_enabled then
		local gp = ground_under_screen(player:footPosition())
		if gp then
			packed[#characters + 1] = { gp[1], gp[2], gp[3], player.grassRadius }
		end
	end

	grassShader:send("character_positions", unpack(packed))
end

-- Setup ----------------------------------------------------------------------

local function send_cloud_params(shader)
	shader:send("cloud_noise", textures.cloud_noise)
	shader:send("light_direction", light_state.direction)
	for name, value in pairs(CLOUD_PARAMS) do
		shader:send(name, value)
	end
end

local function send_lighting_uniforms()
	local dir = light_state.direction
	local light_color = {
		light_state.color[1] * light_state.energy,
		light_state.color[2] * light_state.energy,
		light_state.color[3] * light_state.energy,
	}
	-- Keep the grass blades, grass ground patches, and floor on the same toon
	-- band. The billboard grass uses a camera-facing normal, so the ground uses
	-- that same stylized term to keep the time-of-day tint cohesive.
	local scene_ndotl = clamp(dot3(CAM_Z, dir), 0.12, 1.0)

	grassShader:send("u_light_color", light_color)
	grassShader:send("u_ndotl", scene_ndotl)
	grassShader:send("light_direction", dir)

	grassGroundShader:send("u_light_color", light_color)
	grassGroundShader:send("u_ndotl", scene_ndotl)
	grassGroundShader:send("light_direction", dir)

	floorShader:send("u_light_color", light_color)
	floorShader:send("u_ndotl", scene_ndotl)
	floorShader:send("light_direction", dir)

	capsuleShader:send("light_direction", dir)
	capsuleShader:send("u_albedo", light_color) -- white albedo scaled by light energy

	playerShader:send("u_light_view", { dot3(dir, CAM_X), dot3(dir, CAM_Y), dot3(dir, CAM_Z) })
	playerShader:send("u_light_color", light_color)
	playerShader:send("light_direction", dir)
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
	for name, value in pairs(GRASS_PARAMS) do
		send_if_present(grassGroundShader, name, value)
	end
	send_cloud_params(grassGroundShader)

	floorShader:send("u_view", "column", view)
	floorShader:send("u_proj", "column", proj)
	floorShader:send("albedo2_noise", textures.albedo2_noise)
	floorShader:send("albedo3_noise", textures.albedo3_noise)
	for name, value in pairs(FLOOR_PARAMS) do
		send_if_present(floorShader, name, value)
	end
	send_cloud_params(floorShader)

	capsuleShader:send("u_view", "column", view)
	capsuleShader:send("u_proj", "column", proj)
	capsuleShader:send("u_alpha", 0.3) -- Godot transparency = 0.7

	-- Player sprite: light its normal map with the world light expressed in the
	-- camera's view space (the space the billboard normals were captured in).
	playerShader:send("normal_map", textures.player_normal)
	-- cuts/wrap/steepness/threshold_gradient_size: same toon bands as the floor,
	-- so the cloud shadow on the player matches the shadows on the ground.
	for name, value in pairs(FLOOR_PARAMS) do
		send_if_present(playerShader, name, value)
	end
	send_cloud_params(playerShader)
	send_lighting_uniforms()
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
	local force_no_instancing = false
	local quality_arg
	for _, a in ipairs(args or {}) do
		if a == "--shot" then
			screenshot_timer = 2.5
		elseif a == "--no-instancing" then
			force_no_instancing = true -- exercise the Pi fallback on a capable GPU
		elseif a:match("^%-%-quality=") then
			quality_arg = a:match("^%-%-quality=(%a+)") -- low | medium | high | auto
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

	textures.player_normal = lg.newImage("assets/spritesheet/spritesheet_normal.png")
	textures.player_normal:setFilter("nearest", "nearest")

	grassShader = lg.newShader("shaders/grass.glsl")
	grassGroundShader = lg.newShader("shaders/grass_ground.glsl")
	floorShader = lg.newShader("shaders/floor.glsl")
	capsuleShader = lg.newShader("shaders/capsule.glsl")
	playerShader = lg.newShader("shaders/player.glsl")
	gradeShader = lg.newShader("shaders/grade.glsl")

	instancing = lg.getSupported().instancing and not force_no_instancing

	-- Explicit --quality wins; otherwise (or with "auto") detect from the device.
	local chosen = quality_arg
	if not chosen or chosen == "auto" then
		chosen = detect_quality()
	end
	apply_quality(chosen) -- sets GRASS_COUNT and builds the grass meshes

	print(string.format("[grass] quality=%s, %d blades, instancing=%s", quality, GRASS_COUNT, tostring(instancing)))
	floorMesh = make_floor_mesh()
	capsuleMesh = make_capsule_mesh(0.3, 1.5, 16, 6)

	spawn_characters()
	update_lighting_state()
	send_static_uniforms()
	send_character_positions()

	-- x/y keep the sprite's feet at the spot the scene was tuned for (the 64px
	-- frame at scale 2 is taller than the old placeholder, so it's offset up).
	player = Player.new({
		x = 714,
		y = 496,
		sheet = "assets/spritesheet/spritesheet.png",
		frameWidth = 64,
		frameHeight = 64,
		scale = 2,
		offsetY = -3, -- lift the shadow/contact onto the feet (3px frame padding)
	})
end

function love.update(dt)
	time_elapsed = time_elapsed + dt
	if day_cycle_enabled then
		day_hour = (day_hour + dt * (24.0 / DAY_CYCLE_SECONDS)) % 24.0
	end
	update_lighting_state()
	send_lighting_uniforms()

	player:update(dt)

	-- for _, ch in ipairs(characters) do
	-- 	update_character(ch, dt)
	-- end

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
	elseif key == "g" then
		local i = 1
		for idx, name in ipairs(GRASS_QUALITY_ORDER) do
			if name == quality then
				i = idx
			end
		end
		apply_quality(GRASS_QUALITY_ORDER[(i % #GRASS_QUALITY_ORDER) + 1])
	elseif key == "t" then
		day_cycle_enabled = not day_cycle_enabled
	elseif key == "," then
		day_hour = (day_hour - 0.5) % 24.0
		update_lighting_state()
		send_lighting_uniforms()
	elseif key == "." then
		day_hour = (day_hour + 0.5) % 24.0
		update_lighting_state()
		send_lighting_uniforms()
	elseif key == "[" then
		saturation = clamp(saturation - 0.1, 0.0, 2.0)
	elseif key == "]" then
		saturation = clamp(saturation + 0.1, 0.0, 2.0)
	end
end

function love.draw()
	-- Integer-scale blit params. Needed up here so the 2D player can be drawn
	-- into the 3D canvas (window -> canvas transform) and depth-sorted with the
	-- capsules, then reused for the final blit.
	local w, h = lg.getDimensions()
	local scale = math.max(1, math.floor(math.min(w / VIEW_W, h / VIEW_H)))
	local ox = math.floor((w - VIEW_W * scale) * 0.5)
	local oy = math.floor((h - VIEW_H * scale) * 0.5)

	lg.setCanvas({ canvas, depth = true })
	lg.clear(light_state.sky[1], light_state.sky[2], light_state.sky[3], 1.0, true, true)
	lg.setDepthMode("lequal", true)
	lg.setMeshCullMode("none")
	lg.setColor(1, 1, 1, 1)

	floorShader:send("u_time", time_elapsed)
	lg.setShader(floorShader)
	lg.draw(floorMesh)

	grassGroundShader:send("u_time", time_elapsed)
	lg.setDepthMode("lequal", false)
	lg.setShader(grassGroundShader)
	draw_grass(grassGroundMesh)

	grassShader:send("u_time", time_elapsed)
	lg.setDepthMode("lequal", true)
	lg.setShader(grassShader)
	draw_grass(grassMesh)

	-- Translucent capsules + the 2D player sprite, depth-tested but not written,
	-- drawn back to front so they y/z-order against each other. The player is a
	-- screen-space sprite, so it's drawn via a window->canvas transform (which
	-- also undoes the blit's y-flip) at its projected ground depth.
	lg.setDepthMode("lequal", false)
	lg.setShader(capsuleShader)

	local order = {}
	for _, ch in ipairs(characters) do
		order[#order + 1] = { depth = camera_depth(ch.pos[1], ch.pos[3]), ch = ch }
	end
	local pgp = ground_under_screen(player:footPosition())
	order[#order + 1] = { depth = pgp and camera_depth(pgp[1], pgp[3]) or math.huge, player = true }
	table.sort(order, function(a, b)
		return a.depth > b.depth
	end)

	for _, item in ipairs(order) do
		if item.player then
			lg.setShader()
			lg.setDepthMode()
			lg.push()
			lg.translate(-ox / scale, oy / scale + VIEW_H)
			lg.scale(1 / scale, -1 / scale)
			player:drawShadow()
			-- Sprite gets scene lighting + cloud shadow at its ground point.
			playerShader:send("u_time", time_elapsed)
			playerShader:send("u_world_pos", pgp or { 0.0, 0.0, 0.0 })
			lg.setShader(playerShader)
			player:drawSprite()
			lg.pop()
			lg.setDepthMode("lequal", false)
			lg.setShader(capsuleShader)
		else
			local ch = item.ch
			capsuleShader:send("u_model_scale", ch.mesh_scale)
			capsuleShader:send("u_model_offset", { ch.pos[1], ch.pos[2] + ch.mesh_y, ch.pos[3] })
			lg.draw(capsuleMesh)
		end
	end

	lg.setShader()
	lg.setDepthMode()
	lg.setCanvas()

	-- Blit the 3D canvas at an integer scale; gl_Position output needs a y-flip.
	-- The grade shader post-processes the whole scene (saturation) but not the HUD.
	lg.setColor(1, 1, 1, 1)
	gradeShader:send("u_saturation", saturation)
	lg.setShader(gradeShader)
	lg.draw(canvas, ox, oy + VIEW_H * scale, 0, scale, -scale)
	lg.setShader()

	lg.setColor(1, 1, 1, 0.85)
	lg.print(
		"Space: stepped wind ("
			.. tostring(quantised)
			.. ")  |  C: displacement ("
			.. tostring(displacement_enabled)
			.. ")  |  T: time ("
			.. tostring(day_cycle_enabled)
			.. ")  |  , .: scrub  |  Esc: quit",
		12,
		12
	)
	lg.print("N: wind debug  |  R: rescatter  |  G: quality  |  [ ]: saturation", 12, 30)
	lg.print(
		string.format(
			"%d fps, %d blades, %dx%d (%s), sat %.1f, %s, %.0fK",
			love.timer.getFPS(),
			GRASS_COUNT,
			VIEW_W,
			VIEW_H,
			quality,
			saturation,
			format_hour(day_hour),
			light_state.temperature
		),
		12,
		48
	)
end
