#version 450

layout(push_constant) uniform Frame {
    vec2 scale;
    layout(offset = 32) vec4 rect;
} frame;

void main() {
    vec2 corner = vec2(gl_VertexIndex & 1, gl_VertexIndex >> 1);
    vec2 pixel = frame.rect.xy + corner * frame.rect.zw;
    gl_Position = vec4(pixel * frame.scale - 1.0, 0.0, 1.0);
}
