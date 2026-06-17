// Lights the player billboard so it sits in the scene: directional shading from
// the normal map (light transformed into the display camera's view space, which
// is the space the sprite normals were captured in) plus the same scrolling
// cloud shadows as the ground, sampled at the sprite's world ground point.
// Drawn with LÖVE's default 2D vertex pipeline, so there's no VERTEX stage.

#pragma language glsl3

#define PI 3.14159265358979

uniform Image normal_map; // matches the albedo sheet frame-for-frame
uniform vec3 u_light_view; // scene light direction in view space
uniform vec3 u_light_color;

// Toon stepping shared with floor.glsl, so the cloud shadow on the player is
// quantised with the same bands/thresholds as the shadows on the ground.
uniform int cuts;
uniform float wrap;
uniform float steepness;
uniform float threshold_gradient_size;

// Cloud shadow globals (same maths as floor.glsl), sampled once at u_world_pos.
uniform vec3 u_world_pos; // sprite's ground point in world space
uniform float u_time;
uniform Image cloud_noise;
uniform float cloud_scale;
uniform float cloud_world_y;
uniform float cloud_speed;
uniform float cloud_contrast;
uniform float cloud_threshold;
uniform vec2 cloud_direction;
uniform vec3 light_direction; // world space, for projecting onto the cloud plane
uniform float cloud_shadow_min;
uniform float cloud_diverge_angle;

vec2 rotate_vec2(vec2 v, float angle) {
    float a = angle * (PI / 180.0);
    return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

float get_cloud_noise(vec3 world_pos) {
    float t = (cloud_world_y - world_pos.y) / light_direction.y;
    vec3 hit_pos = world_pos + t * light_direction;
    float inv_scale = 1.0 / cloud_scale;

    vec2 d1 = rotate_vec2(cloud_direction, cloud_diverge_angle);
    vec2 d2 = rotate_vec2(cloud_direction, -cloud_diverge_angle);
    vec2 td1 = u_time * cloud_speed * normalize(d1);
    vec2 td2 = u_time * cloud_speed * normalize(d2);
    float s1 = Texel(cloud_noise, hit_pos.xz * inv_scale + td1).r;
    float s2 = Texel(cloud_noise, hit_pos.xz * (inv_scale * 0.8) + (td2 * 0.89 * PI / 3.0)).r;

    float light_value = clamp(s1 * s2 + cloud_threshold, 0.0, 1.0);
    light_value = (light_value - 0.5) * cloud_contrast + 0.5;
    return clamp(light_value + cloud_threshold, cloud_shadow_min, 1.0);
}

// Identical to floor.glsl so the cloud shadow lands on the same bands.
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

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 albedo = Texel(tex, texture_coords) * color;
    if (albedo.a < 0.02) {
        discard; // keep the silhouette; nothing to light here
    }

    // Directional term from the normal map. Transparent/empty texels decode to a
    // zero-length normal, so fall back to fully lit there.
    vec3 n = Texel(normal_map, texture_coords).xyz * 2.0 - 1.0;
    float ndotl = 1.0;
    if (dot(n, n) > 0.0001) {
        ndotl = max(dot(normalize(n), u_light_view), 0.0);
    }

    // Same pipeline as the ground: combine lighting with the cloud factor via
    // min(), then step. Under a cloud the cloud term wins, so the player resolves
    // to the exact same stepped value as the floor it stands on.
    float diffuse_amount = (ndotl + wrap) * steepness;
    diffuse_amount = min(diffuse_amount, get_cloud_noise(u_world_pos));
    float diffuse_stepped = toon_stepped(diffuse_amount);

    return vec4(albedo.rgb * u_light_color * diffuse_stepped, albedo.a);
}
