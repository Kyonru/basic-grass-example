local FIELD_SIZE = 46
local HALF_FIELD = FIELD_SIZE * 0.5
local BLADE_COUNT = 7000
local MAX_CHARACTERS = 10

local CAMERA_MOVE_SPEED = 18
local CAMERA_ZOOM_STEP = 1.12

local WORLD_SWAY_ANGLE = math.rad(60)
local VIEW_SWAY_ANGLE = math.rad(10)
local VIEW_SWAY_SPEED = 0.1
local FRAMERATE = 10
local WIND_SCALE = 0.07
local WIND_SPEED = 0.025
local WIND_THRESHOLD = 0.365
local RADIUS_EXPONENT = 0.9
local PLAYER_DISPLACEMENT_ANGLE = math.rad(60)
local FAKE_PERSPECTIVE = 0.30

local GRASS_COLOURS = {
    {0.443137, 0.635294, 0.000000},
    {0.556863, 0.678431, 0.211765},
    {0.501961, 0.654902, 0.223529},
}

local GRASS_VARIATIONS = {
    {frequency = 1.000, probability = 0.000},
    {frequency = 0.001, probability = 0.0001},
}

local textures = {}
local blades = {}
local characters = {}
local camera = {
    worldX = 0.0,
    worldZ = 0.0,
    zoom = 1.0,
    screenX = 0.0,
    screenY = 0.0,
}

local show_debug = false
local quantized = true
local time_elapsed = 0.0

local function push_range(value, minv, maxv)
    return math.min(maxv, math.max(minv, value))
end

local function pick_color(x, z)
    local c = (love.math.noise(x * 0.10, z * 0.10, 12.8) + 1.0) * 0.5
    local idx = 1
    if c > 0.66 then
        idx = 3
    elseif c > 0.33 then
        idx = 2
    end
    local base = GRASS_COLOURS[idx]
    local jitter = (love.math.noise(x * 0.40, z * 0.40, 5.3) - 0.5) * 0.07
    return {
        push_range(base[1] + jitter, 0, 1),
        push_range(base[2] + jitter, 0, 1),
        push_range(base[3] + jitter, 0, 1),
    }
end

local function world_to_screen(wx, wz)
    local sx = (wx - camera.worldX) * 14.0 * camera.zoom
    local sz = (wz - camera.worldZ) * 14.0 * camera.zoom
    local screen_x = camera.screenX + (sx - sz) * 0.5
    local screen_y = camera.screenY + (sx + sz) * 0.25
    return screen_x, screen_y
end

local function spawn_character()
    local radius = love.math.random() * 1.5 + 0.35
    return {
        x = love.math.random() * FIELD_SIZE - HALF_FIELD,
        z = love.math.random() * FIELD_SIZE - HALF_FIELD,
        target_x = 0,
        target_z = 0,
        vx = 0,
        vz = 0,
        speed = 6.0,
        acceleration = 20.0,
        wait_timer = 0,
        wait_time = love.math.random() * 0.8 + 0.2,
        radius = 4.8 + radius,
        color = {1.0, 0.72, 0.63},
    }
end

local function pick_new_target(character)
    character.target_x = love.math.random() * FIELD_SIZE - HALF_FIELD
    character.target_z = love.math.random() * FIELD_SIZE - HALF_FIELD
end

local function update_characters(dt)
    for _, character in ipairs(characters) do
        if character.wait_timer > 0 then
            character.wait_timer = character.wait_timer - dt
            if character.wait_timer <= 0 then
                character.wait_timer = 0
                pick_new_target(character)
            end
        else
            local dx = character.target_x - character.x
            local dz = character.target_z - character.z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist < 0.12 then
                character.vx = 0
                character.vz = 0
                character.wait_timer = character.wait_time
            else
                local t = math.min(1.0, dist / 2.0)
                local tx = (dx / dist) * character.speed * t
                local tz = (dz / dist) * character.speed * t
                local avx = (tx - character.vx) * love.math.random()
                local avz = (tz - character.vz) * love.math.random()
                local accel_x = character.acceleration * dt
                local accel_z = character.acceleration * dt
                character.vx = character.vx + avx * (accel_x * 2.0)
                character.vz = character.vz + avz * (accel_z * 2.0)
                character.vx = push_range(character.vx, -character.speed, character.speed)
                character.vz = push_range(character.vz, -character.speed, character.speed)
                character.x = character.x + character.vx * dt
                character.z = character.z + character.vz * dt
            end
        end

        character.x = push_range(character.x, -HALF_FIELD, HALF_FIELD)
        character.z = push_range(character.z, -HALF_FIELD, HALF_FIELD)
    end
end

local function build_field()
    if love.math.setRandomSeed then
        love.math.setRandomSeed(os.time(), os.time())
    else
        math.randomseed(os.time())
    end
    for i = 1, BLADE_COUNT do
        local wx = love.math.random() * FIELD_SIZE - HALF_FIELD
        local wz = love.math.random() * FIELD_SIZE - HALF_FIELD
        local accent_roll = love.math.random()
        local use_acc = textures.accent
        local scale = 0.6 + (love.math.random() * 0.4)
        local color = pick_color(wx, wz)
        if accent_roll < 0.0001 then
            scale = scale * 1.2
        end

        table.insert(blades, {
            x = wx,
            z = wz,
            height = 0.7 + love.math.random() * 0.9,
            base_scale = scale,
            yaw = (love.math.random() - 0.5) * 0.4,
            seed = love.math.random() * 9999.0,
            phase = love.math.random(),
            texture = (accent_roll < 0.003) and use_acc or textures.grass,
            color = color,
        })
    end

    table.sort(blades, function(a, b)
        return (a.x + a.z) < (b.x + b.z)
    end)

    for i = 1, MAX_CHARACTERS do
        local character = spawn_character()
        pick_new_target(character)
        table.insert(characters, character)
    end
end

local function build_character_influence(blade)
    local influence_x = 0.0
    local influence_z = 0.0
    for _, character in ipairs(characters) do
        local dx = blade.x - character.x
        local dz = blade.z - character.z
        local dist2 = dx * dx + dz * dz
        local radius = character.radius
        if dist2 < radius * radius and dist2 > 0.0001 then
            local dist = math.sqrt(dist2)
            local strength = 1.0 - (dist / radius)
            if strength > 0 then
                strength = push_range(strength, 0.0, 1.0) ^ RADIUS_EXPONENT
                local inv = 1.0 / dist
                influence_x = influence_x + dx * inv * strength
                influence_z = influence_z + dz * inv * strength
            end
        end
    end

    return influence_x, influence_z
end

local function draw_characters()
    for _, character in ipairs(characters) do
        local sx, sy = world_to_screen(character.x, character.z)
        local radius = 2.8 * camera.zoom
        love.graphics.setColor(character.color[1], character.color[2], character.color[3], 1)
        love.graphics.circle("fill", sx, sy - (radius * 10), radius + 0.5, 16)
        love.graphics.setColor(1, 0.95, 0.65, 0.6)
        love.graphics.circle("line", sx, sy - (radius * 10), character.radius * 2.3 * camera.zoom, 24)
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("line", sx, sy, character.radius * 0.6 * camera.zoom, 16)
    end
end

local function draw_grass()
    local wind_noise_base = WIND_SPEED * time_elapsed
    for _, blade in ipairs(blades) do
        local t = time_elapsed + blade.phase
        if quantized then
            local frame = 1.0 / FRAMERATE
            t = math.floor((t) / frame + 0.5) * frame
        end

        local n1 = love.math.noise((blade.x + HALF_FIELD) * WIND_SCALE + wind_noise_base,
                                   (blade.z + HALF_FIELD) * WIND_SCALE + t * 0.25)
        local n2 = love.math.noise((blade.x + HALF_FIELD) * (WIND_SCALE * 0.8) + t * 0.22,
                                   (blade.z + HALF_FIELD) * (WIND_SCALE * 0.8) + 11.7)
        local wind = (((n1 * n2) + WIND_THRESHOLD) - 0.5) * 2.0
        local wind_angle = wind * WORLD_SWAY_ANGLE

        local view_angle = math.sin((t + blade.seed) * VIEW_SWAY_SPEED * 2.0 * math.pi)
        view_angle = view_angle * VIEW_SWAY_ANGLE

        local base_angle = wind_angle + blade.yaw + view_angle
        local ix, iz = build_character_influence(blade)
        local mag = math.sqrt(ix * ix + iz * iz)
        local final_angle = base_angle
        if mag > 0.0001 then
            local disp_ang = math.atan2(iz, ix)
            local k = push_range(mag, 0.0, 1.0)
            final_angle = base_angle * (1.0 - k) + disp_ang * k
            final_angle = final_angle + (k * PLAYER_DISPLACEMENT_ANGLE * 0.08)
        end

        local sx, sy = world_to_screen(blade.x, blade.z)
        local depth_bias = (blade.x + blade.z) / FIELD_SIZE
        local perspective = 1.0 + FAKE_PERSPECTIVE * (0.5 - depth_bias)
        local base_scale = blade.base_scale * camera.zoom * perspective
        local h = blade.height * base_scale
        local tex = blade.texture
        local tw, th = tex:getDimensions()
        if sx > -tw and sx < love.graphics.getWidth() + tw and sy > -th and sy < love.graphics.getHeight() + th then
            love.graphics.setColor(blade.color[1], blade.color[2], blade.color[3], 1.0)
            love.graphics.draw(tex, sx, sy, final_angle, base_scale, h, tw * 0.5, th)
        end
    end
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setTitle("Stylised 3D Pixel Grass - Love2D Port")

    textures.grass = love.graphics.newImage("Textures and Materials/grassleaf.png")
    textures.accent = love.graphics.newImage("Textures and Materials/accentleaf.png")

    local bg = {0.42, 0.58, 0.25}
    love.graphics.setBackgroundColor(bg[1], bg[2], bg[3], 1)

    camera.screenX = love.graphics.getWidth() * 0.5
    camera.screenY = love.graphics.getHeight() * 0.52
    camera.worldX = 0.0
    camera.worldZ = -6.0

    build_field()
end

function love.update(dt)
    time_elapsed = time_elapsed + dt
    local mx, mz = 0.0, 0.0
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then
        mx = mx - 1
    end
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then
        mx = mx + 1
    end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then
        mz = mz - 1
    end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then
        mz = mz + 1
    end

    if mx ~= 0 or mz ~= 0 then
        local inv = 1.0 / math.sqrt(2.0)
        if mx ~= 0 and mz ~= 0 then
            mx = mx * inv
            mz = mz * inv
        end
        local pan = CAMERA_MOVE_SPEED * dt / camera.zoom
        camera.worldX = camera.worldX + mx * pan
        camera.worldZ = camera.worldZ + mz * pan
    end

    update_characters(dt)
end

function love.wheelmoved(_x, y)
    if y > 0 then
        camera.zoom = push_range(camera.zoom * CAMERA_ZOOM_STEP, 0.45, 3.0)
    elseif y < 0 then
        camera.zoom = push_range(camera.zoom / CAMERA_ZOOM_STEP, 0.45, 3.0)
    end
end

function love.keypressed(key)
    if key == "space" then
        quantized = not quantized
    elseif key == "f1" then
        show_debug = not show_debug
    elseif key == "r" then
        blades = {}
        characters = {}
        build_field()
        time_elapsed = 0.0
    end
end

function love.draw()
    draw_grass()
    draw_characters()

    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print("WASD/Arrows: Pan  |  Mouse Wheel: Zoom  |  Space: Toggle stepped wind  |  R: Regenerate  |  F1: Debug", 12, 12)
    love.graphics.print("Stepped wind: " .. tostring(quantized), 12, 30)

    if show_debug then
        love.graphics.print("characters: " .. tostring(#characters), 12, 52)
        love.graphics.print("time: " .. string.format("%.2f", time_elapsed), 12, 70)
        love.graphics.print("camera: " .. string.format("%.2f, %.2f", camera.worldX, camera.worldZ), 12, 88)
        love.graphics.print("zoom: " .. string.format("%.2f", camera.zoom), 12, 106)
    end
end
