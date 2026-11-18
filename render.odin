package fluid

import "core:math"

FRect :: struct {x, y, w, h: f32}
IRect :: struct {x, y, w, h: i32}
Vertex :: struct {position: [2]f32, color: [4]f32}

@(private="package")
Draw_Vertex :: struct {
	using vertex: Vertex,
	mask_position: [2]f32,
	mask: [2]u32, // Byte offset and row width. A zero width selects solid color.
}

@(private="package")
Draw_Batch :: struct {
	clip: IRect,
	first, count: u32,
}

// Intersect the current clip with a physical-pixel rectangle and return the
// previous clip for restoration after the drawing operation.
render_clip :: proc(renderer: ^Renderer, rect: IRect) -> IRect {
	previous := renderer.clip
	renderer.clip = intersect_pixels(previous, rect)
	return previous
}

restore_render_clip :: proc(renderer: ^Renderer, previous: IRect) {
	renderer.clip = previous
}

@(private="package")
intersect_pixels :: proc(a, b: IRect) -> IRect {
	x, y := max(a.x, b.x), max(a.y, b.y)
	return {x, y, max(0, min(a.x + a.w, b.x + b.w) - x), max(0, min(a.y + a.h, b.y + b.h) - y)}
}

render_fill_rect :: proc(renderer: ^Renderer, rect: FRect, color: Color) {
	if rect.w > 0 && rect.h > 0 && color.a > 0 {
		quad := [4][2]f32{{rect.x, rect.y}, {rect.x + rect.w, rect.y},
			{rect.x + rect.w, rect.y + rect.h}, {rect.x, rect.y + rect.h}}
		render_quad(renderer, quad, render_color(color))
	}
}

render_rect :: proc(renderer: ^Renderer, rect: FRect, color: Color) {
	if rect.w <= 2 || rect.h <= 2 {
		render_fill_rect(renderer, rect, color)
		return
	}
	render_fill_rect(renderer, {rect.x, rect.y, rect.w, 1}, color)
	render_fill_rect(renderer, {rect.x, rect.y + rect.h - 1, rect.w, 1}, color)
	render_fill_rect(renderer, {rect.x, rect.y + 1, 1, rect.h - 2}, color)
	render_fill_rect(renderer, {rect.x + rect.w - 1, rect.y + 1, 1, rect.h - 2}, color)
}

render_geometry :: proc(renderer: ^Renderer, vertices: []Vertex, indices: []i32) {
	if !render_can_draw(renderer) || len(indices) == 0 {
		return
	}
	assert(len(indices) % 3 == 0)
	base := u32(len(renderer.vertices))
	for vertex in vertices {
		append(&renderer.vertices, Draw_Vertex{vertex = vertex})
	}
	render_batch(renderer, len(indices))
	for index in indices {
		assert(index >= 0 && int(index) < len(vertices))
		append(&renderer.indices, base + u32(index))
	}
}

@(private="package")
render_mask :: proc(renderer: ^Renderer, pos: [2]f32, size: [2]i32, alpha: []u8, color: Color) {
	if !render_can_draw(renderer) || color.a == 0 || size.x <= 0 || size.y <= 0 ||
		len(alpha) < int(size.x) * int(size.y) {
		return
	}
	x, y := i32(math.round(pos.x)), i32(math.round(pos.y))
	clip := renderer.clip
	left, top := max(x, clip.x), max(y, clip.y)
	right, bottom := min(x + size.x, clip.x + clip.w), min(y + size.y, clip.y + clip.h)
	w, h := right - left, bottom - top
	if w <= 0 || h <= 0 {
		return
	}
	offset := len(renderer.masks)
	for row in top..<bottom {
		start := int(row - y) * int(size.x) + int(left - x)
		append(&renderer.masks, ..alpha[start:start + int(w)])
	}
	quad := [4][2]f32{{f32(left), f32(top)}, {f32(right), f32(top)},
		{f32(right), f32(bottom)}, {f32(left), f32(bottom)}}
	render_quad(renderer, quad, render_color(color), {u32(offset), u32(w)})
}

@(private="file")
render_quad :: proc(renderer: ^Renderer, points: [4][2]f32, color: [4]f32, mask: [2]u32 = {}) {
	if !render_can_draw(renderer) {
		return
	}
	base := u32(len(renderer.vertices))
	for point in points {
		append(&renderer.vertices, Draw_Vertex{
			vertex = {point, color}, mask_position = point - points[0], mask = mask,
		})
	}
	render_batch(renderer, 6)
	append(&renderer.indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

@(private="file")
render_can_draw :: proc(renderer: ^Renderer) -> bool {
	return renderer != nil && renderer.recording && renderer.clip.w > 0 && renderer.clip.h > 0
}

@(private="file")
render_batch :: proc(renderer: ^Renderer, count: int) {
	if len(renderer.batches) > 0 {
		last := &renderer.batches[len(renderer.batches) - 1]
		if last.clip == renderer.clip {
			last.count += u32(count)
			return
		}
	}
	append(&renderer.batches, Draw_Batch{
		clip = renderer.clip, first = u32(len(renderer.indices)), count = u32(count),
	})
}

@(private="file")
render_color :: proc(color: Color) -> [4]f32 {
	return [4]f32{f32(color.r), f32(color.g), f32(color.b), f32(color.a)} / 255
}
