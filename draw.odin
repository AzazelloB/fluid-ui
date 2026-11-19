package fluid

// Draw without presenting, so applications can composite their own effects.
draw :: proc(app: ^UI, window: ^Window) {
	for id in app.order {
		element := get_element(app, id)
		if element.window != window || element.hidden {
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

pixel_rect :: proc(r: Pins, scale: f32) -> FRect {
	return {r.left * scale, r.top * scale, width(r) * scale, height(r) * scale}
}

draw_surface :: proc(renderer: ^Renderer, pixels: FRect, style: Style,
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
draw_focus :: proc(renderer: ^Renderer, pixels: FRect, color: Color) {
	render_rect(renderer, pixels, color)
}

@(private="package")
present_window :: proc(window: ^Window) -> bool {
	if !render_begin(window.renderer, window.drawable_size, window.background) {
		return false
	}
	draw(window.ui, window)
	effect := window.effect
	if effect.draw != nil {
		effect.draw(effect.data, window, f32(effect.elapsed / effect.duration))
	}
	clip: Maybe(Window_Circle)
	when platform_clips_drawable {
		if circle, clipped := window.clip.?; clipped {
			scale := pixel_scale(window)
			clip = Window_Circle{circle.center * scale, circle.radius * scale}
		}
	}
	return render_present(window.renderer, clip)
}
