package elements

import "core:math"
import "core:os"
import fluid ".."

Caption_Button :: enum {Close, Minimize, Maximize}

@(private="file")
Caption_State :: struct {
	button: Caption_Button,
	option: bool,
}

// The application supplies the button's position and hit area.
caption_button :: proc(window: ^fluid.Window, pins: fluid.Pins, button: Caption_Button) -> fluid.Element_ID {
	state := new(Caption_State, os.heap_allocator())
	state.button = button
	id := fluid.create_element(window, {
		pins = pins,
		draw = draw_caption_button,
		behavior = {state = state, input = caption_input, destroy = destroy_caption},
	})
	when ODIN_OS == .Windows {
		if button == .Maximize {
			fluid.set_window_hit(window.ui, id, .Maximize)
		}
	}
	return id
}

@(private="file")
destroy_caption :: proc(data: rawptr) {
	free(data, os.heap_allocator())
}

@(private="file")
caption_input :: proc(data: rawptr, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Element_Event) -> bool {
	pointer, ok := event.(fluid.Pointer_Event)
	if !ok {
		return false
	}
	state := cast(^Caption_State)data
	switch pointer.kind {
	case .Down:
		state.option = .Alt in pointer.modifiers
		fluid.capture_pointer(ui, id)
	case .Up:
		if pointer.inside {
			window := fluid.element_window(ui, id)
			switch state.button {
			case .Close: _ = fluid.window_action(window, .Close)
			case .Minimize: _ = fluid.window_action(window, .Minimize)
			case .Maximize:
				action := fluid.Window_Action.Toggle_Maximize
				when ODIN_OS == .Darwin {
					if !state.option || fluid.window_state(window) == .Fullscreen {
						action = .Toggle_Fullscreen
					}
				}
				_ = fluid.window_action(window, action)
			}
		}
	case .Move, .Cancel:
	}
	return true
}

@(private="file")
draw_caption_button :: proc(view: fluid.Element_View) {
	button := cast(^Caption_State)fluid.element_behavior(view.ui, view.id).state
	pixels := fluid.pixel_rect(view.pins, fluid.pixel_scale(view.window))
	density := fluid.pixel_scale(view.window) / fluid.UI_UNIT_POINTS
	center := [2]f32{pixels.x + pixels.w / 2, pixels.y + pixels.h / 2}
	pressed := view.hovered && view.pressed
	active := fluid.window_is_active(view.window)
	when ODIN_OS == .Darwin {
		colors := [Caption_Button]fluid.Color{
			.Close = {255, 95, 87, 255},
			.Minimize = {254, 188, 46, 255},
			.Maximize = {40, 200, 64, 255},
		}
		fill := colors[button.button]
		disabled := button.button == .Minimize && fluid.window_state(view.window) == .Fullscreen
		if !active || disabled {
			fill = {144, 146, 151, 255}
		}
		if pressed && !disabled {
			fill = {u8(u16(fill.r) * 4 / 5), u8(u16(fill.g) * 4 / 5), u8(u16(fill.b) * 4 / 5), 255}
		}
		radius := 6 * density
		fluid.rounded_fill(view.window.renderer, {center.x - radius, center.y - radius, 2 * radius, 2 * radius},
			radius, fill)
		// AppKit reveals all three glyphs as the pointer enters the controls.
		hover := view.ui.hovered
		if !disabled && fluid.valid(view.ui, hover) && fluid.element_window(view.ui, hover) == view.window &&
		   fluid.element_behavior(view.ui, hover).destroy == destroy_caption {
			draw_mac_caption_glyph(view.window, center, density, button.button, pressed && button.option)
		}
	} else {
		ink := active ? fluid.Color{236, 240, 245, 255} : fluid.Color{150, 159, 170, 255}
		if view.hovered {
			fill := pressed ? fluid.Color{255, 255, 255, 38} : fluid.Color{255, 255, 255, 22}
			if button.button == .Close {
				fill = pressed ? fluid.Color{177, 24, 41, 255} : fluid.Color{232, 17, 35, 255}
				ink = {255, 255, 255, 255}
			}
			fluid.render_fill_rect(view.window.renderer, pixels, fill)
		}
		draw_win_caption_glyph(view.window, center, density, button.button, ink)
	}
}

@(private="file")
draw_win_caption_glyph :: proc(window: ^fluid.Window, center: [2]f32, density: f32, button: Caption_Button, ink: fluid.Color) {
	size := math.round(10 * density)
	line := max(f32(1), math.round(density))
	x, y := math.round(center.x - size / 2), math.round(center.y - size / 2)
	switch button {
	case .Close:
		a, b := [2]f32{x + line / 2, y + line / 2}, [2]f32{x + size - line / 2, y + size - line / 2}
		caption_segment(window.renderer, a, b, line, ink)
		caption_segment(window.renderer, {a.x, b.y}, {b.x, a.y}, line, ink)
	case .Minimize:
		fluid.render_fill_rect(window.renderer, {x, math.round(center.y), size, line}, ink)
	case .Maximize:
		if fluid.window_state(window) == .Maximized {
			offset := 2 * line
			size -= offset
			fluid.render_fill_rect(window.renderer, {x + offset, y, size, line}, ink)
			fluid.render_fill_rect(window.renderer, {x + size + offset - line, y + line, line, size - line}, ink)
			y += offset
		}
		r := window.renderer
		fluid.render_fill_rect(r, {x, y, size, line}, ink)
		fluid.render_fill_rect(r, {x, y + size - line, size, line}, ink)
		fluid.render_fill_rect(r, {x, y + line, line, size - 2 * line}, ink)
		fluid.render_fill_rect(r, {x + size - line, y + line, line, size - 2 * line}, ink)
	}
}

@(private="file")
draw_mac_caption_glyph :: proc(window: ^fluid.Window, center: [2]f32, density: f32, button: Caption_Button, option: bool) {
	ink := fluid.Color{0, 0, 0, 155}
	line := max(f32(1), density)
	d := 2.5 * density
	r := window.renderer
	switch button {
	case .Close:
		caption_segment(r, center + {-d, -d}, center + {d, d}, line, ink)
		caption_segment(r, center + {-d, d}, center + {d, -d}, line, ink)
	case .Minimize:
		caption_segment(r, center + {-d, 0}, center + {d, 0}, line, ink)
	case .Maximize:
		if option {
			caption_segment(r, center + {-d, 0}, center + {d, 0}, line, ink)
			caption_segment(r, center + {0, -d}, center + {0, d}, line, ink)
			return
		}
		fullscreen := fluid.window_state(window) == .Fullscreen
		tip_offset := fullscreen ? 0.5 * density : d
		arm := fullscreen ? -d : d
		sides := [?]f32{-1, 1}
		for side in sides {
			tip := center + [2]f32{tip_offset, tip_offset} * side
			delta := arm * side
			caption_segment(r, tip - {delta, 0}, tip, line, ink)
			caption_segment(r, tip - {0, delta}, tip, line, ink)
		}
	}
}

@(private="file")
caption_segment :: proc(renderer: ^fluid.Renderer, a, b: [2]f32, width: f32, ink: fluid.Color) {
	delta := b - a
	offset := [2]f32{-delta.y, delta.x} * (0.5 * width / math.sqrt(delta.x * delta.x + delta.y * delta.y))
	color := [4]f32{f32(ink.r), f32(ink.g), f32(ink.b), f32(ink.a)} / 255
	vertices := [?]fluid.Vertex{{a + offset, color}, {a - offset, color}, {b - offset, color}, {b + offset, color}}
	indices := [?]i32{0, 1, 2, 0, 2, 3}
	fluid.render_geometry(renderer, vertices[:], indices[:])
}
