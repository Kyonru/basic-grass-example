// MIT License.
// LÖVE port of Shaders/Floor.gdshader + Shaders/clouds.gdshaderinc (by Dylearn).
// Flat toon-lit ground with noise colour patches and cloud shadows.

#pragma language glsl3

#define PI 3.14159265358979

varying vec3 v_world_pos;

uniform float u_time;

vec2 rotate_vec2(vec2 vector, float angle) {
    float angle_deg = angle * (PI / 180.0);
    float rotated_x = (vector.x * cos(angle_deg)) - (vector.y * sin(angle_deg));
    float rotated_y = (vector.x * sin(angle_deg)) + (vector.y * cos(angle_deg));
    return vec2(rotated_x, rotated_y);
}

#ifdef VERTEX

uniform mat4 u_view;
uniform mat4 u_proj;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    v_world_pos = vertex_position.xyz; // floor mesh is authored in world space
    return u_proj * (u_view * vec4(vertex_position.xyz, 1.0));
}

#endif

#ifdef PIXEL

uniform vec4 albedo1;
uniform vec4 albedo2;
uniform Image albedo2_noise;
uniform float albedo2_scale;
uniform float albedo2_threshold;
uniform vec4 albedo3;
uniform Image albedo3_noise;
uniform float albedo3_scale;
uniform float albedo3_threshold;

uniform int cuts;
uniform float wrap;
uniform float steepness;
uniform float threshold_gradient_size;
uniform vec3 u_light_color;
uniform float u_ndotl; // shared stylized scene light term, kept in step with grass

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
    float albedo2_noise_tex = Texel(albedo2_noise, v_world_pos.xz * albedo2_scale).r;
    float albedo3_noise_tex = Texel(albedo3_noise, v_world_pos.xz * albedo3_scale).r;
    vec3 ALBEDO = albedo1.rgb;
    if (albedo2_noise_tex > albedo2_threshold) {
        ALBEDO = albedo2.rgb;
    }
    if (albedo3_noise_tex > albedo3_threshold) {
        ALBEDO = albedo3.rgb;
    }

    float diffuse_amount = (u_ndotl + wrap) * steepness;
    diffuse_amount = min(diffuse_amount, get_cloud_noise(v_world_pos));

    // Toon shading with same hybrid stepping as grass.
    float diffuse_stepped = toon_stepped(diffuse_amount);

    return vec4(ALBEDO * u_light_color * diffuse_stepped, 1.0);
}

#endif
