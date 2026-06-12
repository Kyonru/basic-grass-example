// Translucent capsule "characters" (Godot used a default StandardMaterial
// with transparency 0.7, so this is just simple wrapped diffuse).

#pragma language glsl3

varying vec3 v_normal_world;

#ifdef VERTEX

attribute vec3 VertexNormal;

uniform mat4 u_view;
uniform mat4 u_proj;
uniform vec3 u_model_scale;
uniform vec3 u_model_offset;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 world_pos = vertex_position.xyz * u_model_scale + u_model_offset;
    v_normal_world = normalize(VertexNormal / u_model_scale);
    return u_proj * (u_view * vec4(world_pos, 1.0));
}

#endif

#ifdef PIXEL

uniform vec3 light_direction;
uniform vec3 u_albedo;
uniform float u_alpha;

vec4 effect(vec4 vertex_color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    float ndotl = max(dot(normalize(v_normal_world), light_direction), 0.0);
    vec3 colour = u_albedo * (0.35 + 0.65 * ndotl);
    return vec4(colour, u_alpha);
}

#endif
