package elements

import fluid ".."

@(private="package")
Tween :: struct {
	from, target: f32,
	started_at: u64,
}

@(private="package")
ease_out :: proc(t: f32) -> f32 {
	remaining := 1 - t
	return 1 - remaining * remaining * remaining
}

@(private="package")
elapsed_fraction :: proc(now, start, duration: u64) -> f32 {
	return clamp(f32(now - min(now, start)) / f32(duration), 0, 1)
}

@(private="package")
tween_to :: proc(tween: ^Tween, target: f32, now, duration: u64) -> f32 {
	t := ease_out(elapsed_fraction(now, tween.started_at, duration))
	value := tween.from + (tween.target - tween.from) * t
	if tween.target != target {
		tween^ = {from = value, target = target, started_at = now}
	}
	return value
}

@(private="package")
Button_Motion :: struct {
	initialized: bool,
	emphasis, hover, press: Tween,
}

@(private="package")
button_frame :: proc(view: fluid.Element_View, motion: ^Button_Motion, palette: Control_Palette, secondary: bool, now: u64, selected: bool = false) -> fluid.Element_View {
	view := view
	selected_amount := selected ? f32(1) : 0
	hovered := view.hovered ? f32(1) : 0
	pressed := view.pressed ? f32(1) : 0
	if !motion.initialized {
		motion^ = {
			initialized = true,
			emphasis = {from = selected_amount, target = selected_amount},
			hover = {from = hovered, target = hovered},
			press = {from = pressed, target = pressed},
		}
	}
	DURATION :: 150_000_000
	emphasis := tween_to(&motion.emphasis, selected_amount, now, DURATION)
	hover := tween_to(&motion.hover, hovered, now, DURATION)
	press := tween_to(&motion.press, pressed, now, DURATION)
	if view.style.focus_border == nil {
		view.style.focus_border = palette.focus
	}
	if border, styled := view.style.hover_border.?; styled {
		view.style.border = mix_color(view.style.border, border, hover)
		view.style.hover_border = nil
	}
	view.color = button_color(view.color, palette.selected, emphasis, hover, press)
	if secondary {
		opacity := max(emphasis, hover, press)
		view.surface = opacity > 0
		view.color.a = u8(f32(view.color.a) * opacity)
		view.style.border.a = u8(f32(view.style.border.a) * emphasis)
		view.style.shadow *= emphasis
	}
	return view
}

@(private="package")
button_color :: proc(base, selected: fluid.Color, emphasis, hover, press: f32) -> fluid.Color {
	delta := 12 * hover * (1 - press) - 8 * press
	return {
		u8(clamp(f32(base.r) + (f32(selected.r) - f32(base.r)) * emphasis + delta, 0, 255)),
		u8(clamp(f32(base.g) + (f32(selected.g) - f32(base.g)) * emphasis + delta, 0, 255)),
		u8(clamp(f32(base.b) + (f32(selected.b) - f32(base.b)) * emphasis + delta, 0, 255)),
		base.a,
	}
}

@(private="file")
mix_color :: proc(a, b: fluid.Color, t: f32) -> fluid.Color {
	return {
		u8(f32(a.r) * (1 - t) + f32(b.r) * t),
		u8(f32(a.g) * (1 - t) + f32(b.g) * t),
		u8(f32(a.b) * (1 - t) + f32(b.b) * t),
		u8(f32(a.a) * (1 - t) + f32(b.a) * t),
	}
}
