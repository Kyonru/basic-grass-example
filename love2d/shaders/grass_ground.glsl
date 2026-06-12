// Ground tint pass for matching each grass blade's base colour on the floor.

#pragma language glsl3

#define PI 3.14159265358979

varying vec3 v_object_origin;
varying vec3 v_world_pos;

uniform mat4 u_view;
uniform mat4 u_proj;
uniform float u_time;

uniform Image albedo2_noise;
uniform Image albedo3_noise;

uniform vec4 albedo1;
uniform vec4 albedo2;
uniform float albedo2_scale;
uniform float albedo2_threshold;
uniform vec4 albedo3;
uniform float albedo3_scale;
uniform float albedo3_threshold;
uniform float accent_frequency1;
uniform vec4 accent_albedo1;
uniform float accent_probability2;
uniform vec4 accent_albedo2;

uniform int cuts;
uniform float wrap;
uniform float steepness;
uniform float threshold_gradient_size;
uniform vec3 u_light_color;
uniform float u_ndotl;

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

#ifdef VERTEX

attribute vec3 InstanceOffset;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    v_object_origin = InstanceOffset;
    v_world_pos = InstanceOffset + vec3(vertex_position.x, 0.012, vertex_position.z);
    return u_proj * (u_view * vec4(v_world_pos, 1.0));
}

#endif

#ifdef PIXEL

vec2 rotate_vec2(vec2 vector, float angle) {
    float angle_deg = angle * (PI / 180.0);
    float rotated_x = (vector.x * cos(angle_deg)) - (vector.y * sin(angle_deg));
    float rotated_y = (vector.x * sin(angle_deg)) + (vector.y * cos(angle_deg));
    return vec2(rotated_x, rotated_y);
}

float location_seed(vec2 location) {
    return fract(sin(dot(location, vec2(12.9898, 78.233))) * 43758.5453123);
}

float random(float n) {
    return fract(sin(n * 12.9898) * 43758.5453);
}

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

vec3 grass_colour_for_origin(vec3 object_origin) {
    float albedo2_noise_tex = Texel(albedo2_noise, object_origin.xz * albedo2_scale).r;
    float albedo3_noise_tex = Texel(albedo3_noise, object_origin.xz * albedo3_scale).r;
    vec3 ALBEDO = albedo1.rgb;

    if (albedo2_noise_tex > albedo2_threshold) {
        ALBEDO = albedo2.rgb;
    }
    if (albedo3_noise_tex > albedo3_threshold) {
        ALBEDO = albedo3.rgb;
    }

    float instance_seed = location_seed(object_origin.xz);
    float seed1 = random(instance_seed);
    float seed2 = random(instance_seed + PI);
    if (seed1 < accent_frequency1) {
        ALBEDO = accent_albedo1.rgb;
    } else if (seed2 < accent_probability2) {
        ALBEDO = accent_albedo2.rgb;
    }

    float diffuse_amount = (u_ndotl + wrap) * steepness;
    diffuse_amount = min(diffuse_amount, get_cloud_noise(object_origin));
    return ALBEDO * u_light_color * toon_stepped(diffuse_amount);
}

vec4 effect(vec4 vertex_color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 centered_uv = texture_coords - vec2(0.5);
    float dist = length(centered_uv) * 2.0;
    if (dist > 1.0) discard;

    float alpha = 1.0 - smoothstep(0.65, 1.0, dist);
    return vec4(grass_colour_for_origin(v_object_origin), alpha);
}

#endif
