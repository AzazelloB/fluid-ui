#version 450
#extension GL_GOOGLE_include_directive : require
#include "fluid.frag.glsl"

float hash(float n) {
    n = fract(n * 0.1031);
    n *= n + 33.33;
    return fract(n * (n + n));
}

float noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 t = fract(p);
    t = t * t * (3.0 - 2.0 * t);
    float seed = dot(cell, vec2(1.0, 113.0));
    return mix(mix(hash(seed), hash(seed + 1.0), t.x),
               mix(hash(seed + 113.0), hash(seed + 114.0), t.x), t.y);
}

float leaf(vec2 p, vec2 base, vec2 tip, float width, float bend, float edge) {
    vec2 axis = tip - base;
    vec2 delta = p - base;
    float length_squared = dot(axis, axis);
    float inverse_length = inversesqrt(length_squared);
    float along = dot(delta, axis) / length_squared;
    float across = dot(delta, vec2(-axis.y, axis.x)) * inverse_length;
    float t = clamp((along - 0.16) / 0.84, 0.0, 1.0);
    float taper = t * (1.0 - t) * (4.8 - 2.0 * t);
    float petiole = 0.0045 * (1.0 - smoothstep(0.16, 0.30, along));
    float half_width = max(petiole, width * taper);
    float distance = max(abs(across - bend * taper) - half_width,
                         max(-along, along - 1.0) / inverse_length);
    return 1.0 - smoothstep(-edge, edge, distance);
}

float spray(vec2 p, float seed, float edge) {
    vec2 root = vec2(0.0, 0.88);
    vec2 stem = vec2(0.26, -0.39 - 0.07 * hash(seed));
    vec2 normal = vec2(-stem.y, stem.x);
    vec2 delta = p - root;
    float along = clamp(dot(delta, stem) / dot(stem, stem), 0.0, 1.0);
    float radius = mix(0.009, 0.004, along);
    float branch = 1.0 - smoothstep(radius - edge, radius + edge, length(delta - stem * along));
    for (int i = 0; i < 6; ++i) {
        float t = float(i);
        vec2 base = root + stem * (0.30 + t * 0.105);
        float variation = hash(seed + t * 15.1);
        float side = i % 2 == 0 ? -1.0 : 1.0;
        float span = 0.47 - 0.030 * t + 0.045 * variation;
        // Alternate sides while keeping both sets of leaves angled toward the tip.
        vec2 tip = base + (stem + normal * side * 0.39) * span;
        branch = max(branch, leaf(p, base, tip, 0.017 + 0.004 * variation, side * 0.006, edge));
    }
    return max(branch, leaf(p, root + stem * 0.94, root + stem * 1.39, 0.022, 0.009, edge));
}

vec3 bamboo_layer(vec3 behind, vec2 p, float depth, float layer, float time, float pixel) {
    float spacing = mix(0.098, 0.37, depth);
    float grid = p.x / spacing + hash(layer * 39.7);
    float column = floor(grid);
    float local = fract(grid) - 0.5;
    float seed = column * 17.77 + layer * 53.31;
    float phase = hash(seed + 13.0);
    float from_base = 1.0 - p.y;
    float wind = sin(time * 0.82 + seed * 0.07);
    float lean = (hash(seed + 7.0) - 0.5) * 0.28;
    float center = (phase - 0.5) * 0.19 + from_base * lean + from_base * from_base * wind * 0.038;
    float x = local - center;

    float step = mix(0.116, 0.27, depth) * mix(0.83, 1.19, phase);
    float band = (p.y + phase * 0.27) / step;
    float band_seed = seed + floor(band) * 9.71;
    float node = fract(band);
    float side = hash(band_seed + 2.0) < 0.5 ? -1.0 : 1.0;
    float end = mix(0.78, 1.13, depth) + (phase - 0.5) * 0.15;
    float fade = 1.0 - smoothstep(end - 0.045, end + 0.035, p.y);
    vec3 shade = mix(vec3(0.31, 0.43, 0.35), vec3(0.020, 0.073, 0.055), depth);
    vec3 light = mix(vec3(0.67, 0.73, 0.51), vec3(0.22, 0.40, 0.20), depth);
    float clearing = exp(-abs(p.x - 0.16) * 2.25) * (1.0 - smoothstep(0.25, 1.04, p.y));
    float presence = mix(0.47, 1.0, depth) * fade;
    vec3 color = behind;

    float joint = node - 0.88 + x * 0.31;
    float edge = pixel / spacing;
    // Fit the full spray between the stalk and its column boundary as it sways.
    const float spray_extent = 0.40;
    float spray_scale = min(1.0, (0.46 - center * side) / spray_extent);
    vec2 branch_p = vec2(x * side / spray_scale, joint + 0.88 + x * side * wind * 0.12);
    float spray_edge = edge / spray_scale;
    if (branch_p.x > -0.009 - spray_edge && branch_p.x < spray_extent + spray_edge &&
        branch_p.y > 0.22 - spray_edge && branch_p.y < 0.90 + spray_edge &&
        hash(band_seed + 24.0) > 0.29) {
        float foliage = spray(branch_p, band_seed, spray_edge);
        color = mix(color, mix(shade, light, 0.13 + 0.24 * clearing), foliage * presence);
    }

    float collar = 1.0 - smoothstep(0.007, 0.022, abs(joint));
    float radius = mix(0.033, 0.068, depth) * mix(0.62, 1.33, hash(seed + 11.0));
    radius *= 1.0 + 0.14 * collar - 0.18 * from_base;
    float stalk = 1.0 - smoothstep(radius - edge, radius + edge, abs(x));
    if (stalk > 0.0) {
        float cross_section = clamp(x / radius, -1.0, 1.0);
        float roundness = sqrt(1.0 - cross_section * cross_section);
        float grain = noise(vec2((cross_section + column) * 27.0, p.y * 39.0));
        float rim = 1.0 - smoothstep(0.0, 0.62, abs(cross_section + 0.55));
        float crease = 1.0 - smoothstep(0.008, 0.027, abs(joint - 0.033));
        float gloss = 0.12 + 0.26 * roundness + rim * (0.29 + 0.20 * clearing);
        gloss += collar * 0.36 - crease * 0.30 + (grain - 0.5) * 0.14;
        color = mix(color, mix(shade, light, clamp(gloss, 0.0, 1.0)), stalk * presence);
    }
    return color;
}

vec4 shade(vec2 uv, vec2 size, vec4 data) {
    float time = data.x;
    vec2 p = vec2((uv.x - 0.5) * size.x / size.y, uv.y);
    float pixel = 0.75 / size.y;
    float creek = 1.0 - abs(data.w - 1.0);
    float ridge = max(0.0, data.w - 1.0);
    vec2 sun = p - vec2(0.23 + ridge * 0.13 - creek * 0.15, 0.28);
    float clearing = exp(-dot(sun, sun) * 5.4);
    vec3 shadow = mix(vec3(0.085, 0.265, 0.20), vec3(0.06, 0.31, 0.30), creek);
    vec3 light = mix(vec3(0.78, 0.84, 0.48), vec3(1.0, 0.76, 0.38), ridge);
    vec3 haze = mix(shadow, light, clearing);
    float floor_y = 0.86 + 0.075 * noise(vec2(p.x * 5.3, 7.0));
    float floor_fade = smoothstep(floor_y - 0.075, floor_y + 0.09, p.y);
    vec3 color = mix(haze, vec3(0.048, 0.14, 0.107), floor_fade);

    for (int i = 0; i < 5; ++i) {
        float depth = float(i) * 0.25;
        vec2 drift = data.yz * mix(vec2(0.022, 0.008), vec2(0.12, 0.033), depth);
        color = bamboo_layer(color, p + drift, depth, float(i) + 1.0, time, pixel);
        if (i == 2) {
            vec2 current = p * vec2(4.2, 15.0) + vec2(time * 0.036, time * 0.012);
            float fog = exp(-abs(p.y - 0.69) * 7.4) * (0.12 + 0.30 * noise(current));
            color = mix(color, mix(vec3(0.31, 0.47, 0.37), haze, 0.48), fog);
        }
        if (i == 3) {
            // Light fans through the middle distance, behind the nearest stems.
            float sweep = p.x + p.y * 0.49 + data.y * 0.024;
            vec3 beams = (sweep - vec3(0.38, 0.56, 0.74)) * vec3(13.0, 26.0, 18.0);
            float shafts = dot(exp(-beams * beams), vec3(0.19, 0.13, 0.10));
            color += vec3(0.97, 0.83, 0.46) * shafts * (1.0 - smoothstep(0.25, 0.95, p.y));
        }
    }

    vec2 drifting = p * vec2(33.0, 26.0) + vec2(-time * 0.25, time * 0.14);
    float mote_seed = dot(floor(drifting), vec2(17.0, 59.0));
    vec2 mote = vec2(hash(mote_seed + 8.0), hash(mote_seed + 2.0)) * 0.6 + 0.2;
    float distance = length(fract(drifting) - mote);
    float pollen = (1.0 - smoothstep(0.019, 0.083, distance)) * step(0.78, hash(mote_seed));
    float flicker = 0.58 + 0.42 * sin(time * 0.7 + mote_seed);
    color += vec3(1.0, 0.84, 0.42) * pollen * flicker * clearing * 0.35;

    float vignette = 1.0 - 0.66 * smoothstep(0.2, 0.74, length((uv - vec2(0.55, 0.39)) * vec2(0.95, 1.20)));
    float grain = hash(dot(gl_FragCoord.xy, vec2(0.75488, 0.56984))) - 0.5;
    float lower_shade = smoothstep(0.57, 0.98, uv.y);
    float top_shade = 1.0 - smoothstep(0.015, 0.22, uv.y);
    color = mix(color * vignette, vec3(0.033, 0.085, 0.06), max(lower_shade * 0.38, top_shade * 0.55));
    float radius = size.y * 0.038;
    vec2 edge = abs((uv - 0.5) * size) - size * 0.5 + radius;
    float distance_to_edge = length(max(edge, 0.0)) + min(max(edge.x, edge.y), 0.0) - radius;
    return vec4(color + grain / 255.0, 1.0 - smoothstep(-1.0, 0.0, distance_to_edge));
}
