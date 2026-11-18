// Implement shade in the including fragment shader. Return straight RGBA.
layout(push_constant) uniform Frame {
    layout(offset = 8) vec2 circle_center;
    float circle_radius_squared;
    uint clip_enabled;
    layout(offset = 32) vec4 rect;
    vec4 data;
} fluid_frame;

layout(location = 0) out vec4 fluid_color;

vec4 shade(vec2 uv, vec2 size, vec4 data);

void main() {
    vec2 relative = gl_FragCoord.xy - fluid_frame.circle_center;
    if (fluid_frame.clip_enabled != 0 && dot(relative, relative) > fluid_frame.circle_radius_squared) {
        discard;
    }
    vec2 size = fluid_frame.rect.zw;
    vec2 uv = (gl_FragCoord.xy - fluid_frame.rect.xy) / size;
    vec4 color = shade(uv, size, fluid_frame.data);
    float alpha = clamp(color.a, 0.0, 1.0);
    fluid_color = vec4(color.rgb * alpha, alpha);
}
