package fluid

import "core:math"
import "vendor:sdl3"

// Draw without presenting, so applications can composite their own effects.
draw :: proc(app: ^UI, window: ^Window) {
	renderer := window.renderer
	sdl3.SetRenderDrawColor(renderer, 17, 23, 32, 255)
	sdl3.RenderClear(renderer)
	sdl3.SetRenderDrawBlendMode(renderer, sdl3.BLENDMODE_BLEND)

	for id in app.active {
		element := get_element(app, id)
		if element.owner.window != window {
			continue
		}
		r := bounds(app, id)
		if width(r) <= 0 || height(r) <= 0 {
			continue
		}
		scale := window.pixel_density * app.base_font_size
		pixels := sdl3.FRect{r.left * scale, r.top * scale, width(r) * scale, height(r) * scale}
		if element.kind != .Label && pixels.w > 0 && pixels.h > 0 {
			style := element.style
			radius := style.radius * scale
			if style.shadow > 0 {
				// Low-opacity layers soften the silhouette without render targets.
				for i := 8; i > 0; i -= 1 {
					spread := f32(i) * style.shadow * scale / 8
					shadow := sdl3.FRect{pixels.x - spread, pixels.y - spread + style.shadow * scale * 0.4,
						pixels.w + spread * 2, pixels.h + spread * 2}
					rounded_fill(renderer, shadow, radius + spread, {0, 0, 0, 5})
				}
			}
			color := background(app, id)
			border_color := style.border
			if app.hovered == int(id) {
				if hover_color, ok := style.hover_border.?; ok {
					border_color = hover_color
				}
			}
			border := min(style.border_width * scale, min(pixels.w, pixels.h) / 2)
			if border > 0 && border_color.a > 0 {
				rounded_fill(renderer, pixels, radius, border_color)
				inner := sdl3.FRect{pixels.x + border, pixels.y + border, pixels.w - border * 2, pixels.h - border * 2}
				rounded_fill(renderer, inner, max(f32(0), radius - border), color)
			} else {
				rounded_fill(renderer, pixels, radius, color)
			}
		}
		if len(element.label) > 0 {
			draw_label(window, element, r)
		}
	}
}

// Convex rounded silhouette with a one-physical-pixel alpha fringe. No shaders,
// textures, or per-frame heap allocation; density scaling happens at the caller.
@(private="package")
rounded_fill :: proc(renderer: ^sdl3.Renderer, rect: sdl3.FRect, requested_radius: f32, color: Color) {
	if rect.w <= 0 || rect.h <= 0 || color.a == 0 {
		return
	}
	radius := clamp(requested_radius, 0, min(rect.w, rect.h) / 2)
	if radius == 0 {
		sdl3.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
		pixels := rect
		sdl3.RenderFillRect(renderer, &pixels)
		return
	}
	STEPS :: 12
	COUNT :: (STEPS + 1) * 4
	vertices: [1 + COUNT * 2]sdl3.Vertex
	indices: [COUNT * 9]i32
	c := sdl3.FColor{f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
	vertices[0] = {position = {rect.x + rect.w / 2, rect.y + rect.h / 2}, color = c}
	centers := [4][2]f32{
		{rect.x + rect.w - radius, rect.y + radius},
		{rect.x + rect.w - radius, rect.y + rect.h - radius},
		{rect.x + radius, rect.y + rect.h - radius},
		{rect.x + radius, rect.y + radius},
	}
	for corner in 0..<4 {
		for step in 0..=STEPS {
			i := corner * (STEPS + 1) + step
			a := (f32(corner - 1) + f32(step) / STEPS) * math.PI / 2
			direction := [2]f32{math.cos(a), math.sin(a)}
			inner := centers[corner] + direction * radius
			outer := centers[corner] + direction * (radius + 1)
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
	sdl3.RenderGeometry(renderer, nil, raw_data(vertices[:]), len(vertices), raw_data(indices[:]), len(indices))
}
