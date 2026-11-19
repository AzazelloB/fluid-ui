#version 450
#extension GL_GOOGLE_include_directive : require
#include "mask.glsl"

layout(push_constant) uniform Frame {
    vec2 scale;
    uvec2 window_mask;
} frame;

layout(location = 0) in vec4 fragment_color;
layout(location = 1) in vec2 fragment_mask_position;
layout(location = 2) flat in uvec2 fragment_mask;
layout(location = 0) out vec4 pixel_color;

void main() {
    if (!window_pixel_visible(frame.window_mask, gl_FragCoord.xy)) {
        discard;
    }
    float alpha = fragment_color.a;
    uint width = fragment_mask.y;
    if (width != 0) {
        uvec2 position = uvec2(fragment_mask_position);
        uint index = fragment_mask.x + position.y * width + position.x;
        uint coverage = mask_byte(index);
        alpha *= float(coverage) / 255.0;
    }
    pixel_color = vec4(fragment_color.rgb * alpha, alpha);
}
