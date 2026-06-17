// Post-process colour grade applied when the 3D canvas is blitted to the window
// (so it covers the whole scene but not the HUD). Currently just saturation, for
// a washed-out "bad weather" look; this is the natural place to later add an
// overcast tint / darkening to sell rain.

#pragma language glsl3

uniform float u_saturation; // 1.0 = unchanged, 0.0 = greyscale, >1 = punchier

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 c = Texel(tex, texture_coords) * color;
    float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114)); // Rec.601 perceptual grey
    return vec4(mix(vec3(luma), c.rgb, u_saturation), c.a);
}
