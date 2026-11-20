package fluid

import "core:math"

Text_Style :: struct {
	pixels: f32,
	bold: bool,
}

@(private="file")
wrap_width_pixels :: proc(width, scale: f32) -> i32 {
	return max(i32(1), i32(width * scale))
}

measure_text :: proc(window: ^Window, label: string, size: f32 = 1,
	weight: Text_Weight = .Regular, wrap_width: f32 = 0,
) -> (f32, f32) {
	scale := pixel_scale(window)
	text := create_text(text_font(window, size, weight), label)
	if text == nil {
		return 0, 0
	}
	defer native_text_destroy(text)
	if wrap_width > 0 {
		_ = set_wrap_width(text, wrap_width_pixels(wrap_width, scale))
	}
	pixels := text_dimensions(text)
	return f32(pixels[0]) / scale, f32(pixels[1]) / scale
}

text_line_height :: proc(window: ^Window, size: f32 = 1, weight: Text_Weight = .Regular) -> f32 {
	font := text_font(window, size, weight)
	_, line_height := text_font_metrics(font.pixels, font.bold)
	return f32(line_height) / pixel_scale(window)
}

text_font :: proc(window: ^Window, size: f32, weight: Text_Weight) -> Text_Style {
	return {size * pixel_scale(window), weight == .Bold}
}

create_text :: proc(font: Text_Style, label: string) -> ^Text {
	return native_text_create(label, font.pixels, font.bold)
}

// Cached text follows its element's style and window scale.
element_text :: proc(view: Element_View, placeholder: string = "") -> ^Text {
	assert(valid(view.ui, view.id))
	appearance := element_appearance(view.ui, view.id)
	if appearance == nil {
		if placeholder == "" {
			return nil
		}
		appearance = ensure_appearance(view.ui, view.id)
	}
	content := appearance.label != "" ? appearance.label : placeholder
	if content == "" {
		return nil
	}
	return cached_text(&appearance.text, text_font(view.window, appearance.text_size, appearance.text_weight), content)
}

cached_text :: proc(cache: ^^Text, font: Text_Style, label: string) -> ^Text {
	if cache^ == nil {
		cache^ = create_text(font, label)
	}
	return cache^
}

@(private="package")
update_cached_text :: proc(cache: ^^Text, label: string) {
	if cache^ == nil {
		return
	}
	if label == "" {
		release_cached_text(cache)
		return
	}
	native_text_set_string(cache^, label)
}

// Draw text at a physical pixel position.
paint_text :: proc(renderer: ^Renderer, text: ^Text, color: Color, x, y: f32) {
	if text == nil || color.a == 0 {
		return
	}
	clip := renderer.clip
	visible := IRect{clip.x - i32(math.round(x)), clip.y - i32(math.round(y)), clip.w, clip.h}
	offset, size, alpha := native_text_mask(text, visible)
	if len(alpha) > 0 {
		render_mask(renderer, {x + f32(offset[0]), y + f32(offset[1])}, size, alpha, color)
	}
}

// Draw text in UI-unit bounds with alignment and wrapping.
draw_label :: proc(window: ^Window, text: ^Text, rect: Pins, color: Color,
	align: Text_Align = .Center, wrap: bool = false,
) {
	if text == nil {
		return
	}
	scale := pixel_scale(window)
	if !set_wrap_width(text, wrap ? wrap_width_pixels(width(rect), scale) : 0) {
		return
	}
	pixels := text_dimensions(text)
	x := rect.left * scale
	switch align {
	case .Left:
	case .Center: x += (width(rect) * scale - f32(pixels[0])) / 2
	case .Right: x = rect.right * scale - f32(pixels[0])
	}
	if wrap {
		left := i32(math.round(rect.left * scale))
		top := i32(math.round(rect.top * scale))
		clip := IRect{left, top, max(i32(0), i32(math.round(rect.right * scale)) - left),
			max(i32(0), i32(math.round(rect.bottom * scale)) - top)}
		previous_clip := render_clip(window.renderer, clip)
		paint_text(window.renderer, text, color, math.round(x), f32(top))
		restore_render_clip(window.renderer, previous_clip)
	} else {
		y := math.round(rect.top * scale + (height(rect) * scale - f32(pixels[1])) / 2)
		paint_text(window.renderer, text, color, math.round(x), y)
	}
}

release_cached_text :: proc(cache: ^^Text) {
	if cache^ != nil {
		native_text_destroy(cache^)
		cache^ = nil
	}
}

@(private="package")
release_window_text :: proc(window: ^Window) {
	for ids in ([2][]Element_ID{window.ui.order[:], window.ui.hidden[:]}) {
		for id in ids {
			element := get_element(window.ui, id)
			if element.window == window {
				release_element_text(window.ui, id)
			}
		}
	}
}

@(private="package")
release_element_text :: proc(app: ^UI, id: Element_ID) {
	element := get_element(app, id)
	if appearance := element_appearance(app, id); appearance != nil {
		release_cached_text(&appearance.text)
	}
	if element.behavior.release_graphics != nil {
		element.behavior.release_graphics(element.behavior.state)
	}
}
