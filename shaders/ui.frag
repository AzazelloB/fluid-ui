#version 450

layout(push_constant) uniform Frame {
    vec2 scale;
    vec2 circle_center;
    float circle_radius_squared;
    uint clip_enabled;
} frame;

layout(set = 0, binding = 0, std430) readonly buffer Masks {
    uint words[];
} masks;

layout(location = 0) in vec4 fragment_color;
layout(location = 1) in vec2 fragment_mask_position;
layout(location = 2) flat in uvec2 fragment_mask;
layout(location = 0) out vec4 pixel_color;

void main() {
    vec2 relative = gl_FragCoord.xy - frame.circle_center;
    if (frame.clip_enabled != 0 && dot(relative, relative) > frame.circle_radius_squared) {
        discard;
    }
    float alpha = fragment_color.a;
    uint width = fragment_mask.y;
    if (width != 0) {
        uvec2 position = uvec2(fragment_mask_position);
        uint index = fragment_mask.x + position.y * width + position.x;
        uint coverage = (masks.words[index / 4] >> ((index % 4) * 8)) & 255;
        alpha *= float(coverage) / 255.0;
    }
    pixel_color = vec4(fragment_color.rgb * alpha, alpha);
}
