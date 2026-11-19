layout(set = 0, binding = 0, std430) readonly buffer Masks {
    uint words[];
} masks;

uint mask_byte(uint index) {
    return (masks.words[index / 4] >> ((index % 4) * 8)) & 255;
}

bool window_pixel_visible(uvec2 mask, vec2 point) {
    uvec2 pixel = uvec2(point);
    return mask.y == 0 || mask_byte(mask.x + pixel.y * mask.y + pixel.x) != 0;
}
