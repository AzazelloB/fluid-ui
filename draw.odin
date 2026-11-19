package fluid

// Draw without presenting, so applications can composite their own effects.
draw :: proc(app: ^UI, window: ^Window) {
	for id in app.order {
		element := get_element(app, id)
		if element.window != window || element.hidden || element.draw == nil {
			continue
		}
		view := make_element_view(app, id, element)
		if width(view.pins) <= 0 || height(view.pins) <= 0 {
			continue
		}
		element.draw(view)
	}
}

pixel_rect :: proc(r: Pins, scale: f32) -> FRect {
	return {r.left * scale, r.top * scale, width(r) * scale, height(r) * scale}
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
