package fluid

import "vendor:sdl3"

// Draw without presenting, so applications can composite their own effects.
draw :: proc(app: ^UI, window: ^Window) {
	renderer := window.renderer
	background := window.background
	sdl3.SetRenderDrawColor(renderer, background.r, background.g, background.b, background.a)
	sdl3.RenderClear(renderer)
	sdl3.SetRenderDrawBlendMode(renderer, sdl3.BLENDMODE_BLEND)

	for id in app.active {
		element := get_element(app, id)
		if coordinate_window(element) != window {
			continue
		}
		view := make_element_view(app, id, element)
		if width(view.pins) <= 0 || height(view.pins) <= 0 {
			continue
		}
		if element.draw != nil {
			element.draw(view)
		} else {
			draw_default(view)
		}
	}
}

draw_default :: proc(view: Element_View) {
	draw_element_surface(view)
	draw_element_label(view)
}

// Draw the styled surface or focus outline from the supplied view.
draw_element_surface :: proc(view: Element_View) {
	scale := pixel_scale(view.window)
	pixels := pixel_rect(view.pins, scale)
	if view.surface {
		draw_surface(view.window.renderer, pixels, view.style, view.color, view.hovered, view.focused, scale)
	} else if view.focused {
		if color, styled := view.style.focus_border.?; styled {
			draw_focus(view.window.renderer, pixels, color)
		}
	}
}

draw_element_label :: proc(view: Element_View) {
	if view.label != "" {
		draw_label(view.window, element_text(view), view.pins, view.text_color, view.text_align, view.text_wrap)
	}
}

pixel_rect :: proc(r: Pins, scale: f32) -> sdl3.FRect {
	return {r.left * scale, r.top * scale, width(r) * scale, height(r) * scale}
}

draw_surface :: proc(renderer: ^sdl3.Renderer, pixels: sdl3.FRect, style: Style,
	color: Color, hovered, focused: bool, scale: f32,
) {
	border_color := style.border
	if hovered {
		if hover_color, ok := style.hover_border.?; ok {
			border_color = hover_color
		}
	}
	border_width := style.border_width
	if focused {
		if focus_border, styled := style.focus_border.?; styled {
			border_color = focus_border
			border_width = max(border_width, 0.0625)
		}
	}
	paint_surface(renderer, pixels, color, border_color,
		style.radius * scale, border_width * scale, style.shadow * scale, style.square_corners)
}

@(private="package")
draw_focus :: proc(renderer: ^sdl3.Renderer, pixels: sdl3.FRect, color: Color) {
	_ = sdl3.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
	pixel_bounds := pixels
	_ = sdl3.RenderRect(renderer, &pixel_bounds)
}
