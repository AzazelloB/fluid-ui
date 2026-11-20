package main

import "core:fmt"
import fluid "../.."
import "../../elements"

sample_rates := [3]f64{0.5, 60, 2048}
habitats := [Site]string{
	.North = "A sheltered grove beneath a dense canopy. The litter layer holds moisture through the afternoon.",
	.Creek = "A low plot beside the creek. Wet ground and overhanging ferns keep this station cool.",
	.Ridge = "An exposed plot on the upper slope. Direct sun warms the air and dries the soil more quickly.",
}

Station_Panels :: struct {
	page, card, artwork, heading, caption, habitat, week_title, week, back: fluid.Element_ID,
	settings_title, settings_art, rate_label, rate, smoothing_label, smoothing, motion_label, motion: fluid.Element_ID,
	card_open, settings_open: bool,
	card_progress: f32,
	forest_motion: f64,
	week_day: int,
	week_site: Site,
	week_ranges: [7][2]f32,
	week_labels: [7]^fluid.Text,
}

create_station_panels :: proc(app: ^Showcase, ui: ^fluid.UI) {
	p := &app.panels
	w := ui.window
	p.forest_motion = 40
	p.page = elements.panel(w, {}, WINDOW_BACKGROUND)
	fluid.set_pointer_behavior(ui, p.page, .Block)
	p.card = field_button(w, "")
	p.artwork = fluid.create_element(w, {draw = draw_bamboo, behavior = {state = &app.forest}})
	p.heading = field_text(w, "", 1, INK, .Bold)
	p.caption = field_text(w, "Site details  ›", TEXT_SMALL, MUTED)
	p.habitat = field_text(w, "", 1.05, MUTED)
	fluid.set_text_wrap(ui, p.habitat)
	p.week_title = field_text(w, "Soil moisture · seven-day range", 1.05, INK, .Bold)
	p.week = fluid.create_element(w, {draw = draw_station_week,
		behavior = {state = app, input = station_week_input, release_graphics = release_week_graphics}})
	p.back = field_button(w, "", .Secondary)
	fluid.set_draw(ui, p.back, draw_station_back)
	p.settings_title = field_text(w, "Settings", 1.85, INK, .Bold)
	p.settings_art = fluid.create_element(w, {draw = draw_bamboo, behavior = {state = &app.forest}})
	p.rate_label = field_text(w, "Sample ingest rate")
	p.rate = field_control(w, elements.select(w, {}, {"0.5 rows/s", "60 rows/s", "2,048 rows/s"}, 0))
	p.smoothing_label = field_text(w, "Fast-feed smoothing")
	p.smoothing = field_control(w, elements.number_input(w, {}, app.telemetry.smoothing,
		{minimum = 0, maximum = 5, step = 0.25, suffix = " s"}))
	p.motion_label = field_text(w, "Canopy parallax")
	p.motion = field_control(w, elements.number_input(w, {}, p.forest_motion,
		{minimum = 0, maximum = 100, step = 5, suffix = "%"}))
	for id in ([]fluid.Element_ID{p.card, p.back}) {
		fluid.on_press(ui, id, app, press_station_panel)
	}
	for id in ([]fluid.Element_ID{p.rate, p.smoothing, p.motion}) {
		elements.on_change(ui, id, app, change_station_setting)
	}
}

press_station_panel :: proc(app: ^Showcase, ui: ^fluid.UI, id: fluid.Element_ID) {
	p := &app.panels
	switch id {
	case p.card:
		p.card_open = true
	case p.back:
		if p.settings_open { p.settings_open = false } else { p.card_open = false }
	case:
		p.settings_open = !p.settings_open
	}
	// A previously dragged notebook may be above the page elements.
	for element in ([]fluid.Element_ID{p.page, p.card, p.artwork, p.heading, p.caption, p.habitat,
		p.week_title, p.week, p.settings_title, p.settings_art, p.rate_label, p.rate, p.smoothing_label, p.smoothing,
		p.motion_label, p.motion, p.back}) {
		fluid.bring_to_front(ui, element)
	}
}

change_station_setting :: proc(app: ^Showcase, ui: ^fluid.UI, change: elements.Control_Change) {
	p := &app.panels
	t := &app.telemetry
	switch change.id {
	case p.rate:
		t.rate_index = change.value.(int)
		elements.set_choice(ui, change.id, t.rate_index)
		for metric in Metric { t.live_values[metric] = reading(t.site, metric, t.sample) }
		refresh_readings(t, ui)
	case p.smoothing:
		t.smoothing = change.value.(f64)
		elements.set_number(ui, change.id, t.smoothing)
		refresh_readings(t, ui)
	case p.motion:
		p.forest_motion = change.value.(f64)
		elements.set_number(ui, change.id, p.forest_motion)
	}
}

update_station_panels :: proc(app: ^Showcase, ui: ^fluid.UI, canopy, area: fluid.Pins, dt: f64) {
	p := &app.panels
	p.card_progress = clamp(p.card_progress + f32(dt) * (p.card_open ? 2.6 : -2.6), 0, 1)
	progress := smoothstep(p.card_progress)
	details := !p.settings_open && p.card_progress > 0.78
	fluid.set_layout(ui, p.page, area)
	fluid.set_color(ui, p.page, {WINDOW_BACKGROUND.r, WINDOW_BACKGROUND.g, WINDOW_BACKGROUND.b,
		p.settings_open ? 255 : u8(progress * 255)})
	fluid.set_hidden(ui, p.page, !p.settings_open && p.card_progress == 0)
	fluid.set_hidden(ui, p.back, !p.settings_open && !details)
	fluid.set_layout(ui, p.back, fluid.rect(area.left, area.top + 0.78, 2.6, 2.4))
	for id in ([]fluid.Element_ID{p.card, p.artwork, p.heading}) {
		fluid.set_hidden(ui, id, p.settings_open)
	}
	fluid.set_hidden(ui, p.caption, p.settings_open || p.card_progress > 0.24)
	fluid.set_hidden(ui, p.habitat, !details)
	chart_opacity := week_opacity(p)
	fluid.set_hidden(ui, p.week_title, p.settings_open || chart_opacity == 0)
	fluid.set_hidden(ui, p.week, p.settings_open || chart_opacity == 0)
	title_color := INK
	title_color.a = u8(255 * chart_opacity)
	fluid.set_text_style(ui, p.week_title, 1.05, title_color, .Left, .Bold)
	fluid.set_pointer_behavior(ui, p.week, p.card_progress >= 1 ? .Auto : .Pass)
	for id in ([]fluid.Element_ID{p.settings_title, p.settings_art, p.rate_label, p.rate, p.smoothing_label, p.smoothing, p.motion_label, p.motion}) {
		fluid.set_hidden(ui, id, !p.settings_open)
	}
	if p.settings_open {
		layout_station_settings(p, ui, area)
		return
	}

	preview := fluid.rect(canopy.left + 0.85, canopy.bottom - 4.5, 13, 3.75)
	hero := fluid.rect(area.left, area.top + 4, fluid.width(area) * 0.57, clamp(fluid.height(area) * 0.43, 13, 20))
	frame := lerp_pins(preview, hero, progress)
	fluid.set_layout(ui, p.card, frame)
	fluid.set_hidden(ui, p.card, p.card_progress >= 1)
	fluid.set_pointer_behavior(ui, p.card, p.card_progress > 0 ? .Block : .Auto)
	fluid.set_layout(ui, p.artwork, lerp_pins(fluid.rect(preview.left + 0.4, preview.top + 0.4, 3, 2.95), hero, progress))

	site := sites[app.site]
	fluid.set_label(ui, p.heading, site.name)
	fluid.set_text_style(ui, p.heading, 1 + progress * 1.1, INK, .Left, .Bold)
	heading := lerp_pins(fluid.rect(preview.left + 3.95, preview.top + 0.5, 8.7, 1.6),
		{hero.right + 1.6, hero.top + 2.4, area.right, hero.top + 5.4}, progress)
	fluid.set_layout(ui, p.heading, heading)
	fluid.set_layout(ui, p.caption, fluid.rect(preview.left + 3.95, preview.top + 2, 8.7, 1))
	fluid.set_label(ui, p.habitat, habitats[app.site])
	fluid.set_layout(ui, p.habitat, {heading.left, heading.bottom + 0.9, area.right - 0.5, hero.bottom})
	offset := (1 - chart_opacity) * 0.65
	fluid.set_layout(ui, p.week_title, {area.left, hero.bottom + 1.1 + offset, area.right, hero.bottom + 3.1 + offset})
	fluid.set_layout(ui, p.week, {area.left, hero.bottom + 3.25 + offset, area.right, area.bottom + offset})
}

layout_station_settings :: proc(p: ^Station_Panels, ui: ^fluid.UI, area: fluid.Pins) {
	x := area.left + 3.5
	y := area.top + 0.45
	right := min(area.right, x + 23.5)
	fluid.set_layout(ui, p.settings_title, {x, y, right, y + 2.9})
	fluid.set_layout(ui, p.settings_art, {right + 2.5, y + 5.5, area.right, y + 17.5})
	labels := [3]fluid.Element_ID{p.rate_label, p.smoothing_label, p.motion_label}
	controls := [3]fluid.Element_ID{p.rate, p.smoothing, p.motion}
	for label, i in labels {
		top := y + 5.5 + f32(i) * 3.5
		fluid.set_layout(ui, label, fluid.rect(x, top, 9.75, 2.5))
		width := i == 0 ? f32(13.25) : 6
		fluid.set_layout(ui, controls[i], fluid.rect(x + 10.25, top, width, 2.5))
	}
}

week_opacity :: proc(p: ^Station_Panels) -> f32 {
	return smoothstep(clamp((p.card_progress - 0.48) / 0.52, 0, 1))
}

draw_station_back :: proc(view: fluid.Element_View) {
	frame := view
	frame.surface = view.hovered || view.pressed
	frame.style.focus_border = LIME
	elements.draw_element_surface(frame)
	scale := fluid.pixel_scale(view.window)
	center := [2]f32{(view.pins.left + view.pins.right) / 2, (view.pins.top + view.pins.bottom) / 2} * scale
	shape := [6][2]f32{{0.13, -0.32}, {0.23, -0.22}, {-0.02, 0},
		{0.23, 0.22}, {0.13, 0.32}, {-0.23, 0}}
	vertices: [6]fluid.Vertex
	for point, i in shape {
		vertices[i] = {center + point * scale, {0.945, 0.969, 0.91, 1}}
	}
	indices := [12]i32{0, 1, 2, 0, 2, 5, 2, 3, 4, 2, 4, 5}
	fluid.render_geometry(view.window.renderer, vertices[:], indices[:])
}

draw_station_week :: proc(view: fluid.Element_View) {
	app := cast(^Showcase)fluid.element_behavior(view.ui, view.id).state
	p := &app.panels
	day := displayed_sample(&app.telemetry) / SAMPLES_PER_DAY
	if day != p.week_day || app.site != p.week_site {
		release_week_graphics(app)
		p.week_day, p.week_site = day, app.site
		for &range, i in p.week_ranges {
			first := (day - 7 + i) * SAMPLES_PER_DAY
			range = {100, 0}
			for sample := first; sample < first + SAMPLES_PER_DAY; sample += 1 {
				value := reading(app.site, .Moisture, sample)
				range = {min(range.x, value), max(range.y, value)}
			}
		}
	}
	window := view.window
	scale := fluid.pixel_scale(window)
	pixels := fluid.pixel_rect(view.pins, scale)
	gap := pixels.w / 7
	usable := max(0, pixels.h - 2.25 * scale)
	lo := sites[app.site].moisture - 15
	color := sites[app.site].color
	opacity := week_opacity(p)
	track := INSET
	track.a = u8(255 * opacity)
	pointer := fluid.pointer_position(window) * scale
	for range, i in p.week_ranges {
		column := pixels.x + f32(i) * gap
		width := min(2.9 * scale, gap * 0.48)
		left := column + (gap - width) / 2
		hovered := view.hovered && pointer.x >= column && pointer.x < column + gap
		bar := color
		bar.a = u8((hovered ? f32(255) : 207) * opacity)
		label_color := hovered ? INK : MUTED
		label_color.a = u8(255 * opacity)
		bottom := pixels.y + usable
		fluid.rounded_fill(window.renderer, {left, pixels.y, width, usable}, 0.38 * scale, track)
		top := bottom - (range.y - lo) / 30 * usable
		height := max(2, (range.y - range.x) / 30 * usable)
		fluid.rounded_fill(window.renderer, {left, top, width, height}, 0.35 * scale, bar)
		font := fluid.text_font(window, TEXT_SMALL, .Regular)
		text := fluid.cached_text(&p.week_labels[i], font,
			fmt.tprintf("D%d   %.0f–%.0f%%", day - 6 + i, range.x, range.y))
		fluid.draw_label(window, text, fluid.rect((pixels.x + f32(i) * gap) / scale,
			bottom / scale + 0.35, gap / scale, 1.25), label_color, .Center)
	}
}

station_week_input :: proc(state: rawptr, ui: ^fluid.UI, id: fluid.Element_ID, event: fluid.Element_Event) -> bool {
	pointer, ok := event.(fluid.Pointer_Event)
	if !ok || pointer.kind != .Down { return false }
	app := cast(^Showcase)state
	pins := fluid.bounds(ui, id)
	fraction := (pointer.point.x - pins.left) / fluid.width(pins)
	column := clamp(int(fraction * 7), 0, 6)
	sample := (app.panels.week_day - 7 + column) * SAMPLES_PER_DAY + SAMPLES_PER_DAY / 2
	app.panels.card_open = false
	open_reading(&app.telemetry, ui, sample)
	return true
}

release_week_graphics :: proc(state: rawptr) {
	app := cast(^Showcase)state
	for &label in app.panels.week_labels { fluid.release_cached_text(&label) }
}
