package fluid

import "core:math"

// Resolve hover and focus borders before painting a surface in physical pixels.
paint_styled_surface :: proc(renderer: ^Renderer, pixels: FRect, style: Style,
	color: Color, hovered, focused: bool, scale: f32,
) {
	border_color := style.border
	if hovered {
		if hover_color, ok := style.hover_border.?; ok {
			border_color = hover_color
		}
	}
	paint_surface(renderer, pixels, color, border_color,
		style.radius * scale, style.border_width * scale, style.shadow * scale, style.square_corners)
	if focus_border, styled := style.focus_border.?; focused && styled {
		rounded_outline(renderer, pixels, style.radius * scale,
			max(style.border_width, 0.0625) * scale, focus_border, style.square_corners)
	}
}

// Draw a surface using physical pixels and caller-resolved colors.
paint_surface :: proc(renderer: ^Renderer, pixels: FRect, fill, border_color: Color,
	radius, border_width, shadow: f32, square_corners: bit_set[Corner] = {},
) {
	if shadow > 0 {
		// Low-opacity layers soften the silhouette without render targets.
		for i := 8; i > 0; i -= 1 {
			spread := f32(i) * shadow / 8
			layer := FRect{pixels.x - spread, pixels.y - spread + shadow * 0.4,
				pixels.w + spread * 2, pixels.h + spread * 2}
			rounded_fill(renderer, layer, radius + spread, {0, 0, 0, 5}, square_corners)
		}
	}
	border := min(border_width, min(pixels.w, pixels.h) / 2)
	if border > 0 && border_color.a > 0 {
		rounded_fill(renderer, pixels, radius, border_color, square_corners)
		inner := FRect{pixels.x + border, pixels.y + border, pixels.w - border * 2, pixels.h - border * 2}
		rounded_fill(renderer, inner, max(f32(0), radius - border), fill, square_corners)
	} else {
		rounded_fill(renderer, pixels, radius, fill, square_corners)
	}
}

// Convex rounded silhouette with a one-physical-pixel alpha fringe. No shaders,
// textures, or per-frame heap allocation; density scaling happens at the caller.
rounded_fill :: proc(renderer: ^Renderer, rect: FRect, requested_radius: f32, color: Color,
	square_corners: bit_set[Corner] = {},
) {
	if rect.w <= 0 || rect.h <= 0 || color.a == 0 {
		return
	}
	radius := clamp(requested_radius, 0, min(rect.w, rect.h) / 2)
	if radius == 0 || square_corners == {.Top_Right, .Bottom_Right, .Bottom_Left, .Top_Left} {
		render_fill_rect(renderer, rect, color)
		return
	}
	STEPS :: 12
	COUNT :: (STEPS + 1) * 4
	vertices: [1 + COUNT * 2]Vertex
	indices: [COUNT * 9]i32
	c := [4]f32{f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
	vertices[0] = {position = {rect.x + rect.w / 2, rect.y + rect.h / 2}, color = c}
	centers := [4][2]f32{
		{rect.x + rect.w - radius, rect.y + radius},
		{rect.x + rect.w - radius, rect.y + rect.h - radius},
		{rect.x + radius, rect.y + rect.h - radius},
		{rect.x + radius, rect.y + radius},
	}
	corners := [4][2]f32{
		{rect.x + rect.w, rect.y}, {rect.x + rect.w, rect.y + rect.h},
		{rect.x, rect.y + rect.h}, {rect.x, rect.y},
	}
	for corner in 0..<4 {
		center := centers[corner]
		arc := radius
		if Corner(corner) in square_corners {
			center = corners[corner]
			arc = 0
		}
		for step in 0..=STEPS {
			i := corner * (STEPS + 1) + step
			a := (f32(corner - 1) + f32(step) / STEPS) * math.PI / 2
			direction := [2]f32{math.cos(a), math.sin(a)}
			inner := center + direction * arc
			outer := center + direction * (arc + 1)
			vertices[1 + i] = {position = {inner[0], inner[1]}, color = c}
			vertices[1 + COUNT + i] = {position = {outer[0], outer[1]}, color = {c[0], c[1], c[2], 0}}
			next := (i + 1) % COUNT
			base := i * 9
			triangle := [9]i32{0, i32(1 + i), i32(1 + next),
				i32(1 + i), i32(1 + COUNT + i), i32(1 + COUNT + next),
				i32(1 + i), i32(1 + COUNT + next), i32(1 + next)}
			copy(indices[base:base + 9], triangle[:])
		}
	}
	render_geometry(renderer, vertices[:], indices[:])
}

// Stroke a rounded rectangle without painting its center.
rounded_outline :: proc(renderer: ^Renderer, rect: FRect, radius, width: f32, color: Color,
	square_corners: bit_set[Corner] = {},
) {
	half := min(rect.w, rect.h) / 2
	if half <= 0 || width <= 0 || color.a == 0 {
		return
	}
	radius := clamp(radius, 0, half)
	width := min(width, half)
	STEPS :: 12
	COUNT :: 4 * (STEPS + 1)
	vertices: [COUNT * 4]Vertex
	indices: [COUNT * 18]i32
	tint := [4]f32{f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
	clear := [4]f32{tint.r, tint.g, tint.b, 0}
	corners := [4][2]f32{{rect.x + rect.w, rect.y}, {rect.x + rect.w, rect.y + rect.h},
		{rect.x, rect.y + rect.h}, {rect.x, rect.y}}
	inward := [4][2]f32{{-1, 1}, {-1, -1}, {1, -1}, {1, 1}}
	for corner in 0..<4 {
		arc := radius
		if Corner(corner) in square_corners { arc = 0 }
		center := corners[corner] + inward[corner] * arc
		for step in 0..=STEPS {
			i := corner * (STEPS + 1) + step
			a := (f32(corner - 1) + f32(step) / STEPS) * math.PI / 2
			normal := [2]f32{math.cos(a), math.sin(a)}
			outer := center + normal * arc
			inner := outer - normal * width
			inset := corners[corner] + inward[corner] * width
			if arc < width {
				inner = inset
			}
			v := i * 4
			vertices[v + 0] = {outer + normal, clear}
			vertices[v + 1] = {outer, tint}
			vertices[v + 2] = {inner, tint}
			vertices[v + 3] = {inner - normal * min(f32(1), half - width), clear}
			next := i32((i + 1) % COUNT * 4)
			for band in 0..<3 {
				k := i32(v + band)
				n := next + i32(band)
				triangles := [6]i32{k, n, k + 1, k + 1, n, n + 1}
				offset := i * 18 + band * 6
				copy(indices[offset:offset + 6], triangles[:])
			}
		}
	}
	render_geometry(renderer, vertices[:], indices[:])
}
