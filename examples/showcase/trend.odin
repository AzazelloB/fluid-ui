package main

import "core:fmt"
import "core:math"
import fluid "../.."
import "../../elements"

NOTE_CURSOR_PULSE :: 0.85

Trend_Span :: enum {Half_Hour, Three_Hours, Day}
Trend_Axes :: struct {
	site: Site,
	metric: Metric,
	span: Trend_Span,
	compare, historical, centered: bool,
}

trend_minutes := [Trend_Span]int{.Half_Hour = 30, .Three_Hours = 180, .Day = 1440}

change_trend_span :: proc(t: ^Telemetry, ui: ^fluid.UI, change: elements.Control_Change) {
	choice := change.value.(int)
	t.span = Trend_Span(choice)
	elements.set_choice(ui, change.id, choice)
	if end, locked := t.anchor.?; locked {
		if t.note_cursor {
			t.anchor = displayed_sample(t) + trend_minutes[t.span]
		} else {
			t.probe = max(displayed_sample(t), end - trend_minutes[t.span] * 2)
		}
		refresh_readings(t, ui)
	}
}

change_comparison :: proc(t: ^Telemetry, ui: ^fluid.UI, change: elements.Control_Change) {
	t.compare = change.value.(bool)
	elements.set_toggle(ui, change.id, t.compare)
	set_telemetry_visibility(t, ui)
}

open_reading :: proc(t: ^Telemetry, ui: ^fluid.UI, sample: int) {
	t.show_samples = false
	t.anchor, t.probe = sample + trend_minutes[t.span], sample
	t.note_cursor = true
	t.cursor_pulse = NOTE_CURSOR_PULSE
	elements.set_choice(ui, t.view_mode, 0)
	set_telemetry_visibility(t, ui)
	refresh_readings(t, ui)
}

trend_axis :: proc(pins: fluid.Pins) -> fluid.Pins {
	return {pins.left + 3.35, pins.top + 0.85, pins.right - 0.9, pins.bottom - 1.65}
}

inspect_trend :: proc(state: rawptr, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Element_Event) -> bool {
	t := cast(^Telemetry)state
	end := t.anchor.? or_else t.sample
	span := trend_minutes[t.span] * 2
	sample := displayed_sample(t)
	#partial switch input in event {
	case fluid.Pointer_Event:
		switch input.kind {
		case .Down:
			fluid.capture_pointer(ui, id)
		case .Move:
			if !fluid.pointer_captured(ui, id) { return false }
		case .Up, .Cancel:
			return false
		}
		axis := trend_axis(fluid.bounds(ui, id))
		fraction := clamp((input.point.x - axis.left) / fluid.width(axis), 0, 1)
		sample = end - span + int(math.round(fraction * (TREND_SAMPLES - 1))) * span / (TREND_SAMPLES - 1)
	case fluid.Keyboard_Event:
		if !input.down { return false }
		#partial switch input.key {
		case .Left: sample -= max(1, span / (TREND_SAMPLES - 1))
		case .Right: sample += max(1, span / (TREND_SAMPLES - 1))
		case: return false
		}
	case: return false
	}
	t.note_cursor, t.cursor_pulse = false, 0
	t.anchor = end
	t.probe = clamp(sample, end - span, min(end, t.sample))
	set_telemetry_visibility(t, ui)
	refresh_readings(t, ui)
	return true
}

trend_duration :: proc(minutes: int) -> string {
	if minutes < 60 { return fmt.tprintf("%d min", minutes) }
	if minutes % 60 == 0 { return fmt.tprintf("%d hr", minutes / 60) }
	return fmt.tprintf("%d hr %02d min", minutes / 60, minutes % 60)
}

draw_trend :: proc(view: fluid.Element_View) {
	t := cast(^Telemetry)fluid.element_behavior(view.ui, view.id).state
	elements.draw_element_surface(view)
	axes := Trend_Axes{t.site, t.metric, t.span, t.compare, t.anchor != nil, t.note_cursor}
	if axes != t.plot_axes {
		release_trend_text(t)
		t.plot_axes = axes
	}
	metric := t.metric
	info := metrics[metric]
	base := baseline(t.site, metric)
	lo, hi := base - info.span, base + info.span
	if metric == .Light { lo = 0 }
	if t.compare {
		for site in Site {
			other := baseline(site, metric)
			if metric != .Light { lo = min(lo, other - info.span) }
			hi = max(hi, other + info.span)
		}
	}

	window := view.window
	scale := fluid.pixel_scale(window)
	chart := fluid.pixel_rect(view.pins, scale)
	axis := fluid.pixel_rect(trend_axis(view.pins), scale)
	x0, x1 := axis.x, axis.x + axis.w
	y0, y1 := axis.y, axis.y + axis.h
	for i in 0..<3 {
		fraction := f32(i) / 2
		y := y0 + (y1 - y0) * fraction
		fluid.render_fill_rect(window.renderer, {x0, y, x1 - x0, 1}, EDGE)
		draw_plot_label(window, &t.plot_labels[i], fmt.tprintf("%.0f", hi - (hi - lo) * fraction), chart.x + 0.65 * scale, y - 0.46 * scale)
	}
	minutes := trend_minutes[t.span]
	middle := trend_duration(minutes / 2)
	labels := [3]string{fmt.tprintf("−%s", trend_duration(minutes)),
		fmt.tprintf("−%s", middle), t.anchor == nil ? "Now" : "End"}
	if t.note_cursor {
		labels = {fmt.tprintf("−%s", middle), "Selected", fmt.tprintf("+%s", middle)}
	}
	for label, i in labels {
		font := fluid.text_font(window, TEXT_SMALL, .Regular)
		text := fluid.cached_text(&t.plot_labels[3 + i], font, label)
		w := f32(fluid.text_dimensions(text).x)
		x := x0 + (x1 - x0) * f32(i) / 2 - w * f32(i) / 2
		fluid.paint_text(window.renderer, text, MUTED, x, y1 + 0.36 * scale)
	}
	if metric == .Moisture && !t.compare {
		limit := f32(t.dry_below[t.site])
		if limit >= lo && limit <= hi {
			y := y1 - (y1 - y0) * (limit - lo) / (hi - lo)
			for x := x0; x < x1; x += 0.6 * scale {
				fluid.render_fill_rect(window.renderer, {x, y, min(0.3 * scale, x1 - x), 1}, CLAY)
			}
		}
	}

	end := t.anchor.? or_else t.sample
	start_sample := end - minutes * 2
	probe := t.probe.? or_else end
	fraction := f32(probe - start_sample) / f32(end - start_sample)
	probe_x := x0 + axis.w * fraction
	if t.probe != nil {
		cursor := t.note_cursor ? LIME : MUTED
		fluid.render_fill_rect(window.renderer, {probe_x, y0, t.note_cursor ? 2 : 1, axis.h}, cursor)
	}
	for site in Site {
		if !t.compare && site != t.site {
			continue
		}
		tint := t.compare ? sites[site].color : info.color
		points: [TREND_SAMPLES][2]f32
		count := 0
		for &point, i in points {
			sample := start_sample + (end - start_sample) * i / (TREND_SAMPLES - 1)
			if sample > t.sample { break }
			count += 1
			value := reading(site, metric, sample)
			point = {x0 + axis.w * f32(i) / (TREND_SAMPLES - 1), y1 - axis.h * (value - lo) / (hi - lo)}
		}
		if count >= 2 { draw_trend_line(window, points[:count], tint, y1, !t.compare) }
		value := reading(site, metric, probe)
		y := y1 - axis.h * (value - lo) / (hi - lo)
		fluid.rounded_fill(window.renderer, {probe_x - 0.2 * scale, y - 0.2 * scale, 0.4 * scale, 0.4 * scale}, 0.2 * scale, tint)
		if t.cursor_pulse > 0 {
			strength := f32(t.cursor_pulse / NOTE_CURSOR_PULSE)
			radius := (0.24 + (1 - strength) * 0.9) * scale
			halo := tint
			halo.a = u8(strength * 210)
			fluid.rounded_outline(window.renderer, {probe_x - radius, y - radius, 2 * radius, 2 * radius}, radius, 0.095 * scale, halo)
		}
	}
}

draw_trend_line :: proc(window: ^fluid.Window, points: [][2]f32, tint: fluid.Color, bottom: f32, shade: bool) {
	scale := fluid.pixel_scale(window)
	half_width := 0.069 * scale
	color := [4]f32{f32(tint.r) / 255, f32(tint.g) / 255, f32(tint.b) / 255, 1}
	clear_color := [4]f32{color.r, color.g, color.b, 0}
	VERTICES_PER_POINT :: 6
	INDICES_PER_SEGMENT :: 24
	vertices: [TREND_SAMPLES * VERTICES_PER_POINT]fluid.Vertex
	indices: [(TREND_SAMPLES - 1) * INDICES_PER_SEGMENT]i32
	previous := trend_normal(points[1] - points[0])
	for point, i in points {
		next := previous
		if i + 1 < len(points) {
			next = trend_normal(points[i + 1] - point)
		}
		// Join the two perpendicular offsets on their bisector. Limit the
		// extension at sharp turns, then feather the outermost physical pixel.
		join := previous + next
		join /= math.sqrt(join.x * join.x + join.y * join.y)
		miter := join / max(f32(0.5), join.x * next.x + join.y * next.y)
		previous = next
		inner, outer := miter * half_width, miter * (half_width + 1)
		base := i * VERTICES_PER_POINT
		vertices[base + 0] = {point, {color.r, color.g, color.b, shade ? 0.20 : 0}}
		vertices[base + 1] = {{point.x, bottom}, {color.r, color.g, color.b, shade ? 0.025 : 0}}
		vertices[base + 2] = {point - outer, clear_color}
		vertices[base + 3] = {point - inner, color}
		vertices[base + 4] = {point + inner, color}
		vertices[base + 5] = {point + outer, clear_color}
		if i + 1 < len(points) {
			v := i32(base)
			n := v + VERTICES_PER_POINT
			segment := [INDICES_PER_SEGMENT]i32{
				v, n, v + 1, v + 1, n, n + 1,
				v + 2, n + 2, v + 3, v + 3, n + 2, n + 3,
				v + 3, n + 3, v + 4, v + 4, n + 3, n + 4,
				v + 4, n + 4, v + 5, v + 5, n + 4, n + 5,
			}
			offset := i * INDICES_PER_SEGMENT
			copy(indices[offset:offset + INDICES_PER_SEGMENT], segment[:])
		}
	}
	fluid.render_geometry(window.renderer, vertices[:len(points) * VERTICES_PER_POINT], indices[:(len(points) - 1) * INDICES_PER_SEGMENT])
}

trend_normal :: proc(delta: [2]f32) -> [2]f32 {
	return [2]f32{-delta.y, delta.x} / math.sqrt(delta.x * delta.x + delta.y * delta.y)
}

draw_plot_label :: proc(window: ^fluid.Window, cache: ^^fluid.Text, label: string, x, y: f32) {
	text := fluid.cached_text(cache, fluid.text_font(window, TEXT_SMALL, .Regular), label)
	fluid.paint_text(window.renderer, text, MUTED, x, y)
}

release_trend_text :: proc(state: rawptr) {
	t := cast(^Telemetry)state
	for &label in t.plot_labels {
		fluid.release_cached_text(&label)
	}
}
