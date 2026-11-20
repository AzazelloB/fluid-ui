package main

import "core:fmt"
import "core:math"
import "core:strings"
import fluid "../.."
import "../../elements"

Metric :: enum {Moisture, Temperature, Light}
Metric_Info :: struct {
	title, unit: string,
	color: fluid.Color,
	span: f32,
}
metrics := [Metric]Metric_Info{
	.Moisture = {"Soil moisture", "%", JADE, 15},
	.Temperature = {"Air temperature", "°C", HONEY, 8},
	.Light = {"Light level", "lx", LIME, 560},
}

SAMPLES_PER_DAY :: 2 * 60 * 24
ARCHIVE_SAMPLES :: 30 * SAMPLES_PER_DAY
TREND_SAMPLES :: 61
ARCHIVE_COLUMNS :: 4

Metric_Tile :: struct {
	button, title, value: fluid.Element_ID,
}

Telemetry :: struct {
	tiles: [Metric]Metric_Tile,
	column_labels: [ARCHIVE_COLUMNS]fluid.Element_ID,
	view_mode, latest, sample_status, readout, chart, archive, range_choice, compare_button: fluid.Element_ID,
	limit_label, limit, alert: fluid.Element_ID,
	metric: Metric,
	show_samples, compare: bool,
	span: Trend_Span,
	anchor, probe: Maybe(int),
	legend: [Site]fluid.Element_ID,
	site: Site,
	sample: int,
	rate_index: int,
	note_cursor: bool,
	cursor_pulse, smoothing, readout_elapsed: f64,
	live_values: [Metric]f32,
	elapsed: f64,
	dry_below: [Site]f64,
	plot_axes: Trend_Axes,
	plot_labels: [6]^fluid.Text,
	archive_text: [ARCHIVE_COLUMNS]^fluid.Text,
	archive_first, archive_count: int,
}

create_telemetry :: proc(app: ^Showcase, ui: ^fluid.UI) {
	t := &app.telemetry
	window := ui.window
	t.sample = ARCHIVE_SAMPLES + 8 * 120
	t.span = .Three_Hours
	t.smoothing = 1.25
	t.dry_below = {.North = 42, .Creek = 58, .Ridge = 35}
	for metric in Metric {
		info := metrics[metric]
		tile := &t.tiles[metric]
		tile.button = field_button(window, "", .Secondary)
		fluid.on_press(ui, tile.button, t, select_metric)
		tile.title = field_text(window, info.title, TEXT_SMALL, MUTED)
		tile.value = field_text(window, "", 1.32, info.color, .Bold)
	}
	t.view_mode = field_control(window, elements.options(window, {}, {"Trend", "Samples"}, 0))
	elements.on_change(ui, t.view_mode, t, change_telemetry_view)
	t.range_choice = field_control(window, elements.options(window, {}, {"30 min", "3 hr", "24 hr"}, int(t.span)))
	elements.on_change(ui, t.range_choice, t, change_trend_span)
	t.compare_button = field_control(window, elements.toggle(window, {}, "Compare sites", false))
	elements.on_change(ui, t.compare_button, t, change_comparison)
	for site in Site {
		t.legend[site] = field_text(window, sites[site].name, TEXT_SMALL, sites[site].color)
	}
	t.latest = field_button(window, "Latest")
	t.sample_status = field_text(window, "Following live", TEXT_SMALL, MUTED, align = .Right)
	fluid.on_press(ui, t.latest, t, seek_latest)
	t.readout = field_text(window, "", TEXT_SMALL, MUTED, align = .Right)
	t.limit_label = field_text(window, "Dry below", TEXT_SMALL, MUTED)
	t.limit = field_control(window, elements.number_input(window, {}, t.dry_below[.North], {minimum = 0, maximum = 100, suffix = "%"}))
	elements.on_change(ui, t.limit, t, change_dry_limit)
	t.alert = field_text(window, "", TEXT_SMALL, JADE, .Bold, .Right)
	t.chart = fluid.create_element(window, {
		draw = draw_trend, color = INSET, surface = true, focusable = true,
		style = {radius = 0.7, border = EDGE, border_width = 0.0625, focus_border = LIME},
		behavior = {state = t, input = inspect_trend, release_graphics = release_trend_text},
	})
	t.archive = elements.create_scroll_view(window, {
		color = INSET, style = {radius = 0.7, border = EDGE, border_width = 0.0625, focus_border = LIME},
		track_color = SURFACE, thumb_color = MUTED, stick_to_end = true,
		state = t, draw = draw_archive, release_graphics = release_archive_text,
	})
	for title, index in ([ARCHIVE_COLUMNS]string{"Time", "Soil (%)", "Air (°C)", "Light (lx)"}) {
		t.column_labels[index] = field_text(window, title, TEXT_SMALL, MUTED, .Bold)
	}
	set_telemetry_visibility(t, ui)
}

select_metric :: proc(t: ^Telemetry, ui: ^fluid.UI, id: fluid.Element_ID) {
	for tile, metric in t.tiles {
		if tile.button == id {
			t.metric = metric
			break
		}
	}
	set_telemetry_visibility(t, ui)
}

change_telemetry_view :: proc(t: ^Telemetry, ui: ^fluid.UI, change: elements.Control_Change) {
	choice := change.value.(int)
	t.show_samples = choice == 1
	if t.show_samples {
		t.anchor, t.probe = nil, nil
		t.note_cursor, t.cursor_pulse = false, 0
	}
	elements.set_choice(ui, change.id, choice)
	set_telemetry_visibility(t, ui)
	refresh_readings(t, ui)
}

set_telemetry_visibility :: proc(t: ^Telemetry, ui: ^fluid.UI) {
	for tile, metric in t.tiles {
		fluid.set_hidden(ui, tile.button, t.show_samples)
		elements.set_button_selected(ui, tile.button, t.metric == metric)
	}
	fluid.set_hidden(ui, t.archive, !t.show_samples)
	fluid.set_label(ui, t.latest, t.show_samples ? "Jump to latest" : "Back to live")
	fluid.set_hidden(ui, t.range_choice, t.show_samples)
	fluid.set_hidden(ui, t.compare_button, t.show_samples)
	for id in t.legend {
		fluid.set_hidden(ui, id, t.show_samples || !t.compare)
	}
	fluid.set_hidden(ui, t.chart, t.show_samples)
	for id in t.column_labels {
		fluid.set_hidden(ui, id, !t.show_samples)
	}
	moisture_trend := !t.show_samples && !t.compare && t.metric == .Moisture
	for id in ([]fluid.Element_ID{t.limit_label, t.limit, t.alert}) {
		fluid.set_hidden(ui, id, !moisture_trend)
	}
}

seek_latest :: proc(t: ^Telemetry, ui: ^fluid.UI, id: fluid.Element_ID) {
	if t.show_samples {
		elements.scroll_to_end(ui, t.archive)
		fluid.focus(ui, t.archive)
		return
	}
	t.anchor, t.probe = nil, nil
	t.note_cursor, t.cursor_pulse = false, 0
	set_telemetry_visibility(t, ui)
	refresh_readings(t, ui)
}

change_dry_limit :: proc(t: ^Telemetry, ui: ^fluid.UI, change: elements.Control_Change) {
	value := change.value.(f64)
	t.dry_below[t.site] = value
	elements.set_number(ui, change.id, value)
	refresh_readings(t, ui)
}

refresh_telemetry :: proc(app: ^Showcase, ui: ^fluid.UI) {
	t := &app.telemetry
	t.site = app.site
	for metric in Metric {
		t.live_values[metric] = reading(t.site, metric, t.sample)
	}
	release_archive_text(t)
	elements.set_number(ui, t.limit, t.dry_below[t.site])
	refresh_readings(t, ui)
}

displayed_sample :: proc(t: ^Telemetry) -> int {
	return t.probe.? or_else (t.anchor.? or_else t.sample)
}

refresh_readings :: proc(t: ^Telemetry, ui: ^fluid.UI) {
	sample := displayed_sample(t)
	for metric in Metric {
		value := reading(t.site, metric, sample)
		if t.anchor == nil && t.rate_index != 0 && t.smoothing > 0 {
			value = t.live_values[metric]
		}
		fluid.set_label(ui, t.tiles[metric].value, fmt.tprintf("%.*f %s", metric == .Light ? 0 : 1, value, metrics[metric].unit))
	}
	dry := f64(reading(t.site, .Moisture, sample)) < t.dry_below[t.site]
	fluid.set_label(ui, t.alert, dry ? "Below threshold" : "")
	fluid.set_text_style(ui, t.alert, TEXT_SMALL, dry ? CLAY : JADE, .Right, .Bold)
}

update_telemetry :: proc(app: ^Showcase, ui: ^fluid.UI, area: fluid.Pins, dt: f64) {
	t := &app.telemetry
	rate := sample_rates[t.rate_index]
	t.elapsed += dt * rate
	steps := int(t.elapsed)
	if steps > 0 {
		t.elapsed -= f64(steps)
		t.sample += steps
	}
	t.cursor_pulse = max(0, t.cursor_pulse - dt)
	if t.rate_index != 0 && t.smoothing > 0 {
		mix := f32(1 - math.exp(-dt / t.smoothing))
		for metric in Metric {
			value := reading(t.site, metric, t.sample)
			t.live_values[metric] += (value - t.live_values[metric]) * mix
		}
		t.readout_elapsed += dt
		if t.readout_elapsed >= 0.2 {
			t.readout_elapsed = 0
			if t.anchor == nil { refresh_readings(t, ui) }
		}
	} else if steps > 0 && t.anchor == nil {
		refresh_readings(t, ui)
	}

	gap :: f32(0.65)
	width := (fluid.width(area) - 2 * gap) / 3
	for tile, metric in t.tiles {
		x := area.left + f32(metric) * (width + gap)
		fluid.set_layout(ui, tile.button, fluid.rect(x, area.top, width, 4.2))
		fluid.set_layout(ui, tile.title, fluid.rect(x + 0.85, area.top + 0.52, width - 1, 1.15))
		fluid.set_layout(ui, tile.value, fluid.rect(x + 0.85, area.top + 1.7, width - 1, 1.95))
	}

	y := area.top + 5
	right := area.right
	fluid.set_layout(ui, t.view_mode, fluid.rect(area.left, y, 8, 2))
	fluid.set_layout(ui, t.range_choice, fluid.rect(area.left + 8.75, y, 11.5, 2))
	fluid.set_layout(ui, t.compare_button, fluid.rect(area.left + 21, y, 7.25, 2))
	fluid.set_layout(ui, t.latest, fluid.rect(right - 7.5, y, 7.5, 2))
	fluid.set_layout(ui, t.sample_status, fluid.rect(right - 9, y, 9, 2))
	following := t.show_samples && elements.scroll_follows_end(ui, t.archive)
	fluid.set_hidden(ui, t.sample_status, !following)
	fluid.set_hidden(ui, t.latest, following || (!t.show_samples && t.anchor == nil))
	plot := fluid.Pins{area.left, y + 2.55, right, area.bottom - 1.95}
	if t.show_samples {
		// Leave room for a column header inside the clipped scroll view.
		fluid.set_layout(ui, t.archive, {plot.left, plot.top + 1.4, plot.right, plot.bottom})
		fluid.set_layout(ui, t.chart, {})
		layout_archive_header(t, ui, plot)
		elements.set_scroll_content(ui, t.archive, f64(t.sample - ARCHIVE_SAMPLES + 1), f64(t.sample + 1), archive_row_height(ui.window))
	} else {
		fluid.set_layout(ui, t.chart, plot)
		fluid.set_layout(ui, t.archive, {})
	}
	if t.show_samples {
		fluid.set_label(ui, t.readout, fmt.tprintf("%g rows/s  ·  %d retained", rate, ARCHIVE_SAMPLES))
	} else if t.anchor != nil {
		fluid.set_label(ui, t.readout, sample_timestamp(displayed_sample(t)))
	} else {
		fluid.set_label(ui, t.readout, "")
	}
	footer := area.bottom - 1.55
	fluid.set_layout(ui, t.limit_label, fluid.rect(area.left, footer, 3.8, 1.55))
	fluid.set_layout(ui, t.limit, fluid.rect(area.left + 4.05, footer, 3.8, 1.55))
	fluid.set_layout(ui, t.alert, fluid.rect(area.left + 8.65, footer, 8.5, 1.55))
	fluid.set_layout(ui, t.readout, fluid.rect(right - 17, footer, 17, 1.55))
	if t.compare && !t.show_samples {
		for site in Site {
			fluid.set_layout(ui, t.legend[site], fluid.rect(area.left + 8 * f32(site), footer, 8, 1.55))
			value := reading(site, t.metric, displayed_sample(t))
			fluid.set_label(ui, t.legend[site], fmt.tprintf("%s  %.*f %s", sites[site].code, t.metric == .Light ? 0 : 1, value, metrics[t.metric].unit))
		}
	}
}

baseline :: proc(site: Site, metric: Metric) -> f32 {
	info := sites[site]
	values := [Metric]f32{.Moisture = info.moisture, .Temperature = info.temperature, .Light = info.light}
	return values[metric]
}

// Regenerate historical readings by sample number so a month of data takes
// the same storage as the latest sample.
reading :: proc(site: Site, metric: Metric, sample: int) -> f32 {
	day := f64(sample) / SAMPLES_PER_DAY
	hour := f64(sample % SAMPLES_PER_DAY) / SAMPLES_PER_DAY
	daylight := max(0, math.sin((hour - 0.25) * 2 * math.PI))
	weather := math.sin(day * 1.9) * 0.55 + math.sin(day * 0.71 + 1.1) * 0.45
	ripple := math.sin(day * 157 + f64(site)*3) * 0.055 + math.sin(day * 491) * 0.025
	base := f64(baseline(site, metric))
	switch metric {
	case .Moisture:
		rain := math.pow(max(0, weather), 2) * 13
		return f32(clamp(base + rain - daylight * (3 + f64(site)*2) + ripple*10, 0, 100))
	case .Temperature:
		warmth := math.sin((hour - 0.34) * 2 * math.PI)
		return f32(base + warmth*(3 + f64(site)) - weather*2.5 + ripple*4)
	case .Light:
		return f32(2 + base * daylight * (0.8 - 0.18*weather + ripple))
	}
	unreachable()
}

ARCHIVE_TEXT_SIZE :: f32(0.78)
ARCHIVE_OVERSCAN :: 6

archive_row_height :: proc(window: ^fluid.Window) -> f64 {
	return fluid.text_line_advance(fluid.text_font(window, ARCHIVE_TEXT_SIZE, .Regular)) / f64(fluid.pixel_scale(window))
}

archive_offset :: proc(column: int, width: f32) -> f32 {
	fractions := [ARCHIVE_COLUMNS]f32{0, 0.39, 0.60, 0.80}
	return width * fractions[column]
}

layout_archive_header :: proc(t: ^Telemetry, ui: ^fluid.UI, plot: fluid.Pins) {
	for id, column in t.column_labels {
		x := plot.left + 0.8 + archive_offset(column, fluid.width(plot) - 2.1)
		fluid.set_layout(ui, id, {x, plot.top, plot.right, plot.top + 1.2})
	}
}

draw_archive :: proc(state: rawptr, viewport: elements.Scroll_Viewport) {
	t := cast(^Telemetry)state
	window := viewport.element.window
	first := int(math.floor(viewport.first))
	end := int(math.ceil(viewport.end))
	if first < t.archive_first || end > t.archive_first + t.archive_count || t.archive_count == 0 {
		block_first := max(t.sample - ARCHIVE_SAMPLES + 1, first - ARCHIVE_OVERSCAN)
		block_end := min(t.sample + 1, end + ARCHIVE_OVERSCAN)
		prepare_archive_text(t, window, block_first, block_end)
	}
	width := f32(viewport.clip.w)
	y := f32(viewport.clip.y) + f32(math.round((f64(t.archive_first) - viewport.first) * viewport.pixels_per_unit))
	for text, column in t.archive_text {
		color := MUTED
		if column > 0 {
			metric := Metric(column - 1)
			color = metrics[metric].color
		}
		fluid.paint_text(window.renderer, text, color, f32(viewport.clip.x) + archive_offset(column, width), y)
	}
}

prepare_archive_text :: proc(t: ^Telemetry, window: ^fluid.Window, first, end: int) {
	release_archive_text(t)
	t.archive_first, t.archive_count = first, end - first
	columns: [ARCHIVE_COLUMNS]strings.Builder
	for &column in columns {
		column = strings.builder_make(context.temp_allocator)
	}
	for sample in first..<end {
		newline := sample + 1 < end
		fmt.sbprintf(&columns[0], "%s", sample_timestamp(sample), newline = newline)
		for metric in Metric {
			fmt.sbprintf(&columns[int(metric) + 1], "%.*f", metric == .Light ? 0 : 1, reading(t.site, metric, sample), newline = newline)
		}
	}
	font := fluid.text_font(window, ARCHIVE_TEXT_SIZE, .Regular)
	for column, index in columns {
		t.archive_text[index] = fluid.create_text(font, strings.to_string(column))
	}
}

release_archive_text :: proc(state: rawptr) {
	t := cast(^Telemetry)state
	for &column in t.archive_text {
		fluid.release_cached_text(&column)
	}
	t.archive_count = 0
}

sample_timestamp :: proc(sample: int) -> string {
	seconds := (sample % SAMPLES_PER_DAY) * 30
	return fmt.tprintf("Day %02d  %02d:%02d:%02d", sample / SAMPLES_PER_DAY + 1, seconds / 3600, seconds / 60 % 60, seconds % 60)
}
