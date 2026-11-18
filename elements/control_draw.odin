package elements

import "core:fmt"
import "core:math"
import fluid ".."
import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// Suggested content width for choice and number controls, including padding.
// Applications still own pins and can constrain this width to their layout.
control_width :: proc(ui: ^fluid.UI, id: fluid.Element_ID) -> f32 {
	element := get_element(ui, id)
	window := element.window
	measure := proc(window: ^fluid.Window, element: Control_View, label: string) -> f32 {
		if label == "" {
			return 0
		}
		w, _ := fluid.measure_text(window, label, element.text_size, element.text_weight)
		return w
	}
	if element.control == nil {
		return measure(window, element, element.label) + 1.5
	}
	switch &state in element.control.state {
	case Choice_Control:
		w: f32
		for item in state.items {
			w = max(w, measure(window, element, item.label))
		}
		return f32(choice_slot_count(&state)) * (w + 1.5)
	case Number_Control:
		if state.editing {
			return max(state.edit_width, measure(window, element, element.label) + 1.5)
		}
		digit, _ := fluid.measure_text(window, "0", element.text_size, element.text_weight)
		display := fmt.tprintf("%v", state.value)
		affixes := measure(window, element, state.options.prefix) + measure(window, element, state.options.suffix)
		return max(measure(window, element, element.label), affixes + digit * f32(len(display))) + 1.5
	case Button_Control, Toggle_Control, Text_Control, Guard_Control:
		return measure(window, element, element.label) + 1.5
	}
	unreachable()
}

@(private="package")
draw_control :: proc(view: fluid.Element_View) {
	control := get_control(view.ui, view.id)
	now := sdl3.GetTicksNS()
	switch &state in control.state {
	case Choice_Control:
		draw_choice(view, &state, now)
	case Button_Control:
		fluid.draw_default(button_frame(view, &control.motion, state.variant == .Secondary, now))
	case Toggle_Control:
		fluid.draw_default(button_frame(view, &control.motion, true, now))
	case Number_Control, Text_Control:
		draw_field(view)
	case Guard_Control:
		frame := button_frame(view, &control.motion, false, now)
		fluid.draw_element_surface(frame)
		scale := fluid.pixel_scale(frame.window)
		draw_guard(frame.window.renderer, fluid.pixel_rect(frame.pins, scale), frame.style.radius * scale, &state, now)
		fluid.draw_element_label(frame)
	}
}

Field_Text_Style :: struct {
	placeholder, selection, caret: fluid.Color,
}

DEFAULT_FIELD_TEXT_STYLE :: Field_Text_Style{
	placeholder = {139, 157, 178, 255},
	selection = {74, 117, 142, 255},
	caret = {174, 230, 213, 255},
}

// Apply the shared field interaction animation to caller-provided styling.
draw_field :: proc(view: fluid.Element_View, style: Field_Text_Style = DEFAULT_FIELD_TEXT_STYLE) {
	control := get_control(view.ui, view.id)
	frame := button_frame(view, &control.motion, false, sdl3.GetTicksNS())
	fluid.draw_element_surface(frame)
	draw_field_text(frame, style)
}

// Draw a field's text, placeholder, selection, caret, and composition using
// the supplied text style. A custom draw callback can paint its own surface.
draw_field_text :: proc(view: fluid.Element_View, style: Field_Text_Style = DEFAULT_FIELD_TEXT_STYLE) {
	control := get_control(view.ui, view.id)
	if control != nil {
		if editor := editor_for(control); editor != nil {
			draw_editor({view, control}, editor, style)
			return
		}
	}
	fluid.draw_element_label(view)
}

confirmation_progress :: proc(ui: ^fluid.UI, id: fluid.Element_ID) -> f32 {
	control := get_control(ui, id)
	assert(control != nil)
	guard := &control.state.(Guard_Control)
	return visible_guard_progress(guard, sdl3.GetTicksNS())
}

@(private="file")
visible_guard_progress :: proc(guard: ^Guard_Control, now: u64) -> f32 {
	target := guard.reset_at != 0 && now >= guard.reset_at ? f32(0) : f32(guard.progress)
	return tween_to(&guard.fill, target, now, 200_000_000)
}

Choice_Slot :: struct {
	pins: fluid.Pins,
	label: string,
	index: int,
	selected: bool,
}

choice_slots :: proc(ui: ^fluid.UI, id: fluid.Element_ID) -> int {
	choice := &get_control(ui, id).state.(Choice_Control)
	return choice_slot_count(choice)
}

// Invalid slots at either end of a select return false. During a drag this
// reports the same neighboring labels and selection that the stock view draws.
choice_slot :: proc(view: fluid.Element_View, slot: int) -> (Choice_Slot, bool) {
	choice := &get_control(view.ui, view.id).state.(Choice_Control)
	return visible_choice_slot(view.pins, choice, slot)
}

@(private="file")
visible_choice_slot :: proc(pins: fluid.Pins, choice: ^Choice_Control, slot: int) -> (Choice_Slot, bool) {
	count := choice_slot_count(choice)
	index := choice_index_at_slot(choice, slot, choice.preview)
	if slot < 0 || slot >= count || index < 0 || index >= len(choice.items) {
		return {}, false
	}
	w := fluid.width(pins) / f32(count)
	r := fluid.rect(pins.left + f32(slot) * w, pins.top, w, fluid.height(pins))
	return {r, choice.items[index].label, index, index == choice.preview}, true
}

@(private="package")
draw_guard :: proc(renderer: ^sdl3.Renderer, pixels: sdl3.FRect, radius: f32, guard: ^Guard_Control, now: u64) {
	progress := visible_guard_progress(guard, now)
	if progress <= 0 {
		return
	}
	fill := pixels
	fill.w *= progress
	clip := sdl3.Rect{i32(fill.x), i32(fill.y), i32(fill.w), i32(fill.h)}
	_ = sdl3.SetRenderClipRect(renderer, &clip)
	fluid.rounded_fill(renderer, pixels, radius, {238, 157, 133, 100})
	_ = sdl3.SetRenderClipRect(renderer, nil)
}

@(private="package")
draw_choice :: proc(element: fluid.Element_View, choice: ^Choice_Control, now: u64) {
	window := element.window
	scale := fluid.pixel_scale(window)
	count := choice_slot_count(choice)
	point: [2]f32
	if element.hovered {
		point = fluid.pointer_position(window)
	}
	slide := ease_out(elapsed_fraction(now, choice.slide_started, 160_000_000))
	offset := choice.slide_direction * 0.65 * (1 - slide)
	text_alpha := 0.55 + 0.45 * slide
	for i in 0..<count {
		slot, visible := visible_choice_slot(element.pins, choice, i)
		if !visible {
			continue
		}
		r := slot.pins
		over := element.hovered && fluid.contains(r, point)
		item := &choice.items[slot.index]
		pixels := fluid.pixel_rect(r, scale)
		if !choice.neighbors || slot.selected {
			view := element
			view.pins = r
			view.selected = slot.selected
			view.focused = element.focused && slot.selected
			view.hovered = over
			view.pressed = element.pressed && over
			if !choice.neighbors {
				if i > 0 {
					view.style.square_corners |= {.Top_Left, .Bottom_Left}
				}
				if i + 1 < count {
					view.style.square_corners |= {.Top_Right, .Bottom_Right}
				}
			}
			fluid.draw_element_surface(button_frame(view, &item.motion, !choice.neighbors, now))
		}
		if item.label == "" {
			continue
		}
		text := fluid.cached_text(window, &item.text,
			fluid.text_font(window, element.text_size, element.text_weight), item.label)
		tint := element.text_color
		tint.a = u8(f32(tint.a) * text_alpha)
		if choice.neighbors && !slot.selected {
			hover := tween_to(&item.hover_tint, over ? 1 : 0, now, 150_000_000)
			draw_neighbor(window.renderer, text, pixels, tint, i == 0, hover, scale, offset)
		} else {
			clip := sdl3.Rect{i32(pixels.x), i32(pixels.y), i32(pixels.w), i32(pixels.h)}
			_ = sdl3.SetRenderClipRect(window.renderer, &clip)
			fluid.draw_label(window, text, fluid.translated(r, {offset, 0}), tint)
			_ = sdl3.SetRenderClipRect(window.renderer, nil)
		}
	}
}

// Adjacent choices are text aligned toward the current value. Clip the same
// cached text into bands so it fades without painting over the backdrop.
@(private="file")
draw_neighbor :: proc(renderer: ^sdl3.Renderer, text: ^ttf.Text, slot: sdl3.FRect,
	color: fluid.Color, previous: bool, hover, scale, offset: f32,
) {
	assert(text != nil)
	w, h: i32
	assert(ttf.GetTextSize(text, &w, &h))
	inset := 0.45 * scale
	aligned_x := previous ? slot.x + slot.w - inset - f32(w) : slot.x + inset
	x := math.round(aligned_x + offset * scale)
	y := math.round(slot.y + (slot.h - f32(h)) / 2)
	text_left := i32(x)
	slot_left, slot_right := i32(slot.x), i32(slot.x + slot.w)
	steps :: 8
	strength := 0.72 + 0.28 * hover
	for band in 0..<steps {
		left := max(slot_left, text_left + w * i32(band) / steps)
		right := min(slot_right, text_left + w * i32(band + 1) / steps)
		if right <= left {
			continue
		}
		toward_center := f32(band) / (steps - 1)
		if !previous {
			toward_center = 1 - toward_center
		}
		tint := color
		tint.a = u8(f32(color.a) * strength * (0.1 + 0.9 * toward_center))
		clip := sdl3.Rect{left, i32(slot.y), right - left, i32(slot.h)}
		_ = sdl3.SetRenderClipRect(renderer, &clip)
		_ = fluid.paint_text(text, tint, x, y)
	}
	_ = sdl3.SetRenderClipRect(renderer, nil)
}
