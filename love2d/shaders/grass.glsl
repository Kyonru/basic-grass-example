// MIT License.
// LÖVE port of Shaders/Grass.gdshader + Shaders/clouds.gdshaderinc (by Dylearn).
// Billboarded grass quads with quantised wind sway, view-space sway,
// character displacement and hybrid toon lighting with cloud shadows.

#pragma language glsl3

#define PI 3.14159265358979

varying vec3 v_object_origin;   // instance origin, world space
varying float v_wind_sample;
varying float v_fake_persp;     // character displacement fake perspective
varying float v_seed1;          // accent 1 instance seed
varying float v_seed2;          // accent 2 instance seed

uniform float u_time;
uniform vec3 camera_forward_world; // CAMERA_DIRECTION_WORLD

uniform bool world_space_sway;
uniform bool character_displacement;
uniform vec2 wind_noise_direction;
uniform float fake_perspective_scale;
uniform float accent_frequency1;
uniform float accent_probability2;

vec2 rotate_vec2(vec2 vector, float angle) {
    float angle_deg = angle * (PI / 180.0);
    float rotated_x = (vector.x * cos(angle_deg)) - (vector.y * sin(angle_deg));
    float rotated_y = (vector.x * sin(angle_deg)) + (vector.y * cos(angle_deg));
    return vec2(rotated_x, rotated_y);
}

#ifdef VERTEX

attribute vec3 InstanceOffset;

uniform mat4 u_view;
uniform mat4 u_proj;

uniform Image wind_noise;
uniform float framerate;
uniform bool quantised;
uniform bool view_space_sway;
uniform float world_sway_angle;        // degrees
uniform float wind_noise_threshold;
uniform float wind_noise_scale;
uniform float wind_noise_speed;
uniform float noise_diverge_angle;     // degrees
uniform float view_sway_speed;         // cycles per second
uniform float view_sway_angle;         // degrees
uniform float player_displacement_angle_z; // degrees
uniform float player_displacement_angle_x; // degrees
uniform float radius_exponent;

#define CHARACTER_COUNT 16
uniform vec4 character_positions[CHARACTER_COUNT]; // xyz = world pos, w = radius

uniform float accent_height1;
uniform float accent_scale1;
uniform float accent_height2;
uniform float accent_scale2;

float location_seed(vec2 location) { // Random value based on world space location
    return fract(sin(dot(location, vec2(12.9898, 78.233))) * 43758.5453123);
}

float random(float n) {
    return fract(sin(n * 12.9898) * 43758.5453);
}

mat3 rotateAroundAxis(vec3 axis, float angle) {
    axis = normalize(axis);
    float c = cos(angle);
    float s = sin(angle);
    float oc = 1.0 - c;

    return mat3(
        vec3(oc * axis.x * axis.x + c,
             oc * axis.x * axis.y - axis.z * s,
             oc * axis.z * axis.x + axis.y * s),

        vec3(oc * axis.x * axis.y + axis.z * s,
             oc * axis.y * axis.y + c,
             oc * axis.y * axis.z - axis.x * s),

        vec3(oc * axis.z * axis.x - axis.y * s,
             oc * axis.y * axis.z + axis.x * s,
             oc * axis.z * axis.z + c));
}

mat3 view_space_rotate(float angle) {
    return mat3(
        vec3(cos(angle), -sin(angle), 0.0),
        vec3(sin(angle), cos(angle), 0.0),
        vec3(0.0, 0.0, 1.0));
}

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 VERTEX = vertex_position.xyz;
    vec3 object_origin = InstanceOffset;
    v_object_origin = object_origin;
    // Generate random numbers for accent leaves based on instance position.
    float instance_seed = location_seed(object_origin.xz);
    v_seed1 = random(instance_seed);
    v_seed2 = random(instance_seed + PI);

    // Accent 1
    if (v_seed1 < accent_frequency1) {
        VERTEX.y += accent_height1;
        VERTEX *= accent_scale1;
    }
    // Accent 2
    else if (v_seed2 < accent_probability2) {
        VERTEX.y += accent_height2;
        VERTEX *= accent_scale2;
    }

    // Random per-blade phase so quantised blades don't all step on the same frame
    float seed = 10.0 * location_seed(object_origin.xy);
    float frametime = 1.0 / framerate;
    float phase = mod(seed, frametime);

    float time = u_time;
    if (quantised) {
        time += phase;
        time = floor(time * framerate + 0.5) / framerate;
    }

    // Two diverging scrolling noises multiplied to avoid visible tiling
    vec2 wind_noise_direction1 = rotate_vec2(wind_noise_direction, noise_diverge_angle);
    vec2 wind_noise_direction2 = rotate_vec2(wind_noise_direction, -noise_diverge_angle);
    vec2 wind_noise_time_direction1 = time * wind_noise_speed * normalize(wind_noise_direction1);
    vec2 wind_noise_time_direction2 = time * wind_noise_speed * normalize(wind_noise_direction2);
    float wind_noise_sample1 = Texel(wind_noise, object_origin.xz * wind_noise_scale + wind_noise_time_direction1).r;
    float wind_noise_sample2 = Texel(wind_noise, object_origin.xz * (wind_noise_scale * 0.8) + (wind_noise_time_direction2 * 0.89 * PI / 3.0)).r;
    float wind_noise_sample = wind_noise_sample1 * wind_noise_sample2;
    wind_noise_sample = clamp(wind_noise_sample + wind_noise_threshold, 0.0, 1.0);
    wind_noise_sample = (wind_noise_sample - 0.5) * 2.0;
    v_wind_sample = wind_noise_sample;

    // World space sway: rotate around the axis perpendicular to the wind, in view space
    float world_sway = wind_noise_sample * radians(world_sway_angle);
    vec3 wind_world_axis = mat3(u_view) * vec3(wind_noise_direction.y, 0.0, -wind_noise_direction.x);
    mat3 world_rotation = rotateAroundAxis(wind_world_axis, world_sway);

    // View space sway: gentle rotation around the camera z axis
    float model_sway = sin((time + seed) * view_sway_speed * 2.0 * PI) * radians(view_sway_angle);
    mat3 model_rotation = view_space_rotate(model_sway);

    // Character displacement: cumulative push away from each nearby character
    float character_displacement_x = 0.0;
    float character_displacement_y = 0.0;
    for (int i = 0; i < CHARACTER_COUNT; i++) {
        if (character_positions[i].w <= 0.0) continue;
        float dist = length(character_positions[i].xyz - object_origin) / character_positions[i].w;
        if (dist >= 1.0) continue;
        float displacement_strength = clamp(pow(1.0 - dist, radius_exponent), 0.0, 1.0);

        vec3 character_to_grass = object_origin - character_positions[i].xyz;
        // Scale rotation per screen axis by alignment with the camera
        float view_y_dot = dot(normalize(camera_forward_world.xz), normalize(character_to_grass.xz));
        vec3 perpendicular_camera_direction_world = vec3(camera_forward_world.z, 0.0, -camera_forward_world.x);
        float view_x_dot = dot(normalize(perpendicular_camera_direction_world.xz), normalize(character_to_grass.xz));

        character_displacement_x += displacement_strength * view_x_dot;
        character_displacement_y += displacement_strength * view_y_dot;
    }
    character_displacement_x = clamp(character_displacement_x, -1.0, 1.0);
    character_displacement_y = clamp(character_displacement_y, -1.0, 1.0);

    mat3 player_displacement_rotation =
        rotateAroundAxis(vec3(0.0, 0.0, 1.0), character_displacement_x * radians(player_displacement_angle_z))
        * rotateAroundAxis(vec3(1.0, 0.0, 0.0), character_displacement_y * radians(player_displacement_angle_x));
    v_fake_persp = character_displacement_y;

    // Billboarding: the rotated vertex lives directly in view space,
    // translated to the instance origin (Godot's modified MODELVIEW_MATRIX)
    if (view_space_sway) {
        VERTEX = model_rotation * VERTEX;
    }
    if (character_displacement) {
        VERTEX = player_displacement_rotation * VERTEX;
    }
    if (world_space_sway) {
        VERTEX = world_rotation * VERTEX;
    }

    vec3 origin_view = (u_view * vec4(object_origin, 1.0)).xyz;
    return u_proj * vec4(VERTEX + origin_view, 1.0);
}

#endif

#ifdef PIXEL

uniform vec4 albedo1;
uniform vec4 albedo2;
uniform float albedo2_scale;
uniform float albedo2_threshold;
uniform Image albedo2_noise;
uniform vec4 albedo3;
uniform float albedo3_scale;
uniform float albedo3_threshold;
uniform Image albedo3_noise;

uniform vec4 accent_albedo1;
uniform Image accent_texture2;
uniform vec4 accent_albedo2;

uniform int cuts;
uniform float wrap;
uniform float steepness;
uniform float threshold_gradient_size;
uniform vec3 u_light_color;
uniform float u_ndotl; // billboard normal faces the camera, so constant per frame

uniform bool debug_noise;

// Cloud shadow globals (clouds.gdshaderinc)
uniform Image cloud_noise;
uniform float cloud_scale;
uniform float cloud_world_y;
uniform float cloud_speed;
uniform float cloud_contrast;
uniform float cloud_threshold;
uniform vec2 cloud_direction;
uniform vec3 light_direction;
uniform float cloud_shadow_min;
uniform float cloud_diverge_angle;

float get_cloud_noise(vec3 world_pos) {
    float t = (cloud_world_y - world_pos.y) / light_direction.y;
    vec3 hit_pos = world_pos + t * light_direction;
    float inv_scale = 1.0 / cloud_scale;

    vec2 cloud_direction1 = rotate_vec2(cloud_direction, cloud_diverge_angle);
    vec2 cloud_direction2 = rotate_vec2(cloud_direction, -cloud_diverge_angle);
    vec2 cloud_time_direction1 = u_time * cloud_speed * normalize(cloud_direction1);
    vec2 cloud_time_direction2 = u_time * cloud_speed * normalize(cloud_direction2);
    float cloud_sample1 = Texel(cloud_noise, hit_pos.xz * inv_scale + cloud_time_direction1).r;
    float cloud_sample2 = Texel(cloud_noise, hit_pos.xz * (inv_scale * 0.8) + (cloud_time_direction2 * 0.89 * PI / 3.0)).r;
    float cloud_sample = cloud_sample1 * cloud_sample2;
    float light_value = clamp(cloud_sample + cloud_threshold, 0.0, 1.0);

    light_value = (light_value - 0.5) * cloud_contrast + 0.5;
    light_value = clamp(light_value + cloud_threshold, cloud_shadow_min, 1.0);
    return light_value;
}

// Hybrid toon shading (gradient near the cut thresholds)
float toon_stepped(float diffuse_amount) {
    float cuts_inv = 1.0 / float(cuts);
    float cut = cuts_inv;
    float original_index = ceil(diffuse_amount * float(cuts));
    float original_stepped = clamp(original_index * cut, 0.0, 1.0);
    float diffuse_stepped = clamp(diffuse_amount + mod(1.0 - diffuse_amount, cuts_inv), 0.0, 1.0);

    if (threshold_gradient_size > 0.0) {
        float nearest_k = floor(diffuse_amount / cut + 0.5);
        float threshold = nearest_k * cut;

        if (nearest_k >= 0.0 && nearest_k <= float(cuts)) {
            float halfWidth = 0.5 * cut * threshold_gradient_size;
            float low = max(0.0, threshold - halfWidth);
            float high = min(1.0, threshold + halfWidth);

            float blend = 0.0;
            if (high > low) {
                blend = smoothstep(low, high, diffuse_amount);
            } else {
                blend = step(threshold, diffuse_amount);
            }

            float leftValue = threshold;
            float rightValue = min(threshold + cut, 1.0);
            diffuse_stepped = clamp(mix(leftValue, rightValue, blend), 0.0, 1.0);
        } else {
            diffuse_stepped = original_stepped;
        }
    }
    return diffuse_stepped;
}

vec4 effect(vec4 vertex_color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;
    // Fake perspective: squish UV.x around the centre, strongest at the tip
    uv.x -= 0.5;
    float _wind_noise_sample = v_wind_sample * fake_perspective_scale;
    if (world_space_sway) {
        _wind_noise_sample *= dot(camera_forward_world.xz, wind_noise_direction);
        uv.x *= (1.0 - uv.y) * _wind_noise_sample + 1.0;
    }
    if (character_displacement) {
        uv.x *= (1.0 - uv.y) * -v_fake_persp + 1.0;
    }
    uv.x += 0.5;
    uv.x = clamp(uv.x, 0.0, 1.0);

    vec4 albedo_tex = Texel(tex, uv);
    float albedo2_noise_tex = Texel(albedo2_noise, v_object_origin.xz * albedo2_scale).r;
    float albedo3_noise_tex = Texel(albedo3_noise, v_object_origin.xz * albedo3_scale).r;
    vec3 ALBEDO = albedo1.rgb * albedo_tex.rgb;
    if (albedo2_noise_tex > albedo2_threshold) {
        ALBEDO = albedo2.rgb;
    }
    if (albedo3_noise_tex > albedo3_threshold) {
        ALBEDO = albedo3.rgb;
    }
    // Accent 1 (uses the main grass texture)
    if (v_seed1 < accent_frequency1) {
        ALBEDO = accent_albedo1.rgb * albedo_tex.rgb;
    }
    // Accent 2
    else if (v_seed2 < accent_probability2) {
        albedo_tex = Texel(accent_texture2, uv);
        ALBEDO = accent_albedo2.rgb * albedo_tex.rgb;
    }

    // ALPHA_SCISSOR_THRESHOLD = 1.0
    if (albedo_tex.a < 1.0) discard;

    // Diffuse toon lighting, clamped by the cloud shadows
    float diffuse_amount = (u_ndotl + wrap) * steepness;
    diffuse_amount = min(diffuse_amount, get_cloud_noise(v_object_origin));
    float diffuse_stepped = toon_stepped(diffuse_amount);

    vec3 colour = ALBEDO * u_light_color * diffuse_stepped;
    if (debug_noise) {
        colour = vec3(v_wind_sample);
    }
    return vec4(colour, 1.0);
}

#endif
