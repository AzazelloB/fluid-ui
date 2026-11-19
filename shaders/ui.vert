#version 450

layout(push_constant) uniform Frame {
    vec2 scale;
} frame;

layout(location = 0) in vec2 position;
layout(location = 1) in vec4 color;
layout(location = 2) in vec2 mask_position;
layout(location = 3) in uvec2 mask;

layout(location = 0) out vec4 fragment_color;
layout(location = 1) out vec2 fragment_mask_position;
layout(location = 2) flat out uvec2 fragment_mask;

void main() {
    gl_Position = vec4(position * frame.scale - 1.0, 0.0, 1.0);
    fragment_color = color;
    fragment_mask_position = mask_position;
    fragment_mask = mask;
}
