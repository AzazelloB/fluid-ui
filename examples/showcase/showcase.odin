package main

import "core:math"
import fluid "../.."

Site :: enum {North, Creek, Ridge}
Site_Info :: struct {
	code, name: string,
	color: fluid.Color,
	marker: [2]f32,
	moisture, temperature, light: f32,
}
sites := [Site]Site_Info{
	.North = {"N1", "North Grove", LIME, {0.22, 0.44}, 54, 21, 890},
	.Creek = {"C2", "Creek Bend", JADE, {0.52, 0.58}, 69, 19, 620},
	.Ridge = {"R3", "Sun Ridge", HONEY, {0.79, 0.40}, 33, 26, 1380},
}

GUTTER :: f32(1.25)

Showcase :: struct {
	launch: Launch_Reveal,
	title_bar: Title_Bar,
	site: Site,
	forest: Bamboo,
	panels: Station_Panels,
	telemetry: Telemetry,
	notebook: Notebook,
	dock_space: [Dock_Side]f32,
}

create_showcase :: proc(app: ^Showcase, ui: ^fluid.UI) {
	window := ui.window
	create_title_bar(&app.title_bar, window)
	create_bamboo(app, ui)
	create_telemetry(app, ui)
	create_notebook(app, ui)
	create_station_panels(app, ui)
	fluid.on_press(ui, app.title_bar.settings, app, press_station_panel)
	app.dock_space[.Right] = NOTEBOOK_WIDTH + GUTTER
	refresh_site(app, ui)
	update_showcase(app, ui, 0)
	fluid.on_update(ui, app.forest.background, app, update_showcase)
	start_launch_reveal(&app.launch, window)
}

select_site :: proc(app: ^Showcase, ui: ^fluid.UI, id: fluid.Element_ID) {
	for site in Site {
		if id != app.forest.markers[site] {
			continue
		}
		if app.site != site {
			app.site = site
			fluid.animate_to(ui, app.forest.ring, marker_ring_pins(&app.forest, ui, site), damped_animation(0.3))
			refresh_site(app, ui)
		}
		return
	}
}

refresh_site :: proc(app: ^Showcase, ui: ^fluid.UI) {
	for site in Site {
		fluid.set_text_style(ui, app.forest.markers[site], TEXT_BODY, app.site == site ? DARK_INK : INK, .Center, .Bold)
	}
	fluid.set_label(ui, app.title_bar.title, sites[app.site].name)
	refresh_telemetry(app, ui)
	refresh_notebook(app, ui)
}

update_showcase :: proc(app: ^Showcase, ui: ^fluid.UI, dt: f64) {
	viewport := fluid.bounds(ui, ui.window.viewport)
	body := viewport
	body.top = TITLE_BAR_HEIGHT
	layout_title_bar(app, ui, viewport)

	area := fluid.Pins{body.left + GUTTER, body.top + 0.375, body.right - GUTTER, body.bottom - GUTTER}
	update_notebook(app, ui, area, dt)
	full_area := area
	for side in Dock_Side {
		target := app.notebook.window == nil && app.notebook.side == side ? NOTEBOOK_WIDTH + GUTTER : 0
		space := &app.dock_space[side]
		space^ += (target - space^) * (1 - math.exp(-16 * f32(dt)))
		if abs(space^ - target) < 0.02 {
			space^ = target
		}
	}
	area.left += app.dock_space[.Left]
	area.right -= app.dock_space[.Right]

	forest_bottom := area.top + clamp(fluid.height(area) * 0.43, 15, 21)
	canopy := fluid.Pins{area.left, area.top, area.right, forest_bottom}
	update_bamboo(app, ui, canopy, dt)
	update_telemetry(app, ui, {area.left, forest_bottom + GUTTER, area.right, area.bottom}, dt)
	update_station_panels(app, ui, canopy, full_area, dt)
	if app.panels.settings_open || app.panels.card_progress >= 1 {
		clear_workspace_layout(app, ui)
	}
}

// Keep the dashboard state while it is off-page. Empty bounds also remove
// dashboard controls from keyboard navigation.
clear_workspace_layout :: proc(app: ^Showcase, ui: ^fluid.UI) {
	forest := &app.forest
	fluid.set_layout(ui, forest.background, {})
	fluid.set_layout(ui, forest.ring, {})
	for id in forest.markers { fluid.set_layout(ui, id, {}) }
	t := &app.telemetry
	for tile in t.tiles {
		for id in ([]fluid.Element_ID{tile.button, tile.title, tile.value}) { fluid.set_layout(ui, id, {}) }
	}
	for id in t.column_labels { fluid.set_layout(ui, id, {}) }
	for id in t.legend { fluid.set_layout(ui, id, {}) }
	for id in ([]fluid.Element_ID{t.view_mode, t.latest, t.sample_status, t.readout, t.chart, t.archive,
		t.range_choice, t.compare_button, t.limit_label, t.limit, t.alert}) {
		fluid.set_layout(ui, id, {})
	}
	n := &app.notebook
	if n.window == nil {
		for id in n.parts { fluid.set_layout(ui, id, {}) }
		fluid.set_layout(ui, n.save, {})
		fluid.set_layout(ui, n.arriving_text, {})
	}
}
