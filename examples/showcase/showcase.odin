package main

import "core:math"
import fluid "../.."
import "../../elements"

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
Workspace_View :: enum {Canopy, Readings, Notebook}
workspace_titles := [Workspace_View]string{.Canopy = "Canopy", .Readings = "Readings", .Notebook = "Notebook"}

Showcase :: struct {
	launch: Launch_Reveal,
	title_bar: Title_Bar,
	site: Site,
	forest: Bamboo,
	panels: Station_Panels,
	telemetry: Telemetry,
	notebook: Notebook,
	dock_space: [Dock_Side]f32,
	workspace_tabs: [Workspace_View]fluid.Element_ID,
	workspace_view: Workspace_View,
	compact: bool,
	focus_target: Maybe(fluid.Element_ID),
	scale: f32,
}

create_showcase :: proc(app: ^Showcase, ui: ^fluid.UI) {
	window := ui.window
	create_title_bar(&app.title_bar, window)
	window.key_fallback = {app, showcase_key}
	for title, view in workspace_titles {
		tab := field_button(window, title, .Secondary)
		app.workspace_tabs[view] = tab
		fluid.on_press(ui, tab, app, select_workspace)
	}
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
	focused := ui.focused
	layout_title_bar(app, ui, viewport)

	area := fluid.Pins{viewport.left + GUTTER, TITLE_BAR_HEIGHT + 0.375, viewport.right - GUTTER, viewport.bottom - GUTTER}
	area = centered_area(area, 105)
	compact := fluid.width(area) < NOTEBOOK_WIDTH + GUTTER + 35 || fluid.height(area) < 32
	if compact && !app.compact {
		if workspace, ok := workspace_for_focus(app, focused).?; ok {
			app.workspace_view = workspace
		}
		app.dock_space = {}
	} else if !compact && app.compact {
		if app.notebook.window == nil {
			app.dock_space[app.notebook.side] = NOTEBOOK_WIDTH + GUTTER
		}
		if focused == app.workspace_tabs[app.workspace_view] {
			app.focus_target = workspace_focus(app)
		}
	}
	app.compact = compact
	modal := app.panels.settings_open || app.panels.card_progress > 0 || app.panels.card_open
	for tab, view in app.workspace_tabs {
		fluid.set_hidden(ui, tab, !compact || modal)
		if compact {
			width := fluid.width(area) / 3
			fluid.set_layout(ui, tab, fluid.rect(area.left + f32(view) * width, area.top, width - 0.25, 2.5))
			elements.set_button_selected(ui, tab, app.workspace_view == view)
		}
	}
	if compact && !modal {
		area.top += 3
	}

	notebook_area := area
	if compact {
		notebook_area = centered_area(area, 34)
	}
	update_notebook(app, ui, notebook_area, dt)
	full_area := area
	for side in Dock_Side {
		target := !compact && app.notebook.window == nil && app.notebook.side == side ? NOTEBOOK_WIDTH + GUTTER : 0
		space := &app.dock_space[side]
		space^ += (target - space^) * (1 - math.exp(-16 * f32(dt)))
		if abs(space^ - target) < 0.02 {
			space^ = target
		}
	}
	area.left += app.dock_space[.Left]
	area.right -= app.dock_space[.Right]

	forest_bottom := area.top + clamp(fluid.height(area) * 0.43, 15, 21)
	if compact {
		forest_bottom = area.bottom
	}
	canopy := fluid.Pins{area.left, area.top, area.right, forest_bottom}
	readings := fluid.Pins{area.left, forest_bottom + GUTTER, area.right, area.bottom}
	if compact {
		readings = centered_area(area, 55)
	}
	update_bamboo(app, ui, canopy, dt)
	update_telemetry(app, ui, readings, dt)
	update_station_panels(app, ui, canopy, full_area, dt)
	covered := app.panels.settings_open || app.panels.card_progress >= 1
	show_canopy := !compact || app.workspace_view == .Canopy
	if covered || !show_canopy {
		clear_canopy_layout(&app.forest, ui)
	}
	if covered || (compact && app.workspace_view != .Readings) {
		clear_telemetry_layout(&app.telemetry, ui)
	}
	if app.notebook.window == nil && (covered || (compact && app.workspace_view != .Notebook)) {
		clear_notebook_layout(&app.notebook, ui)
	}
	if target, ok := app.focus_target.?; ok {
		if has_layout(ui, target) && (!modal || target == app.panels.back) {
			app.focus_target = nil
			fluid.focus(ui, target)
		}
	} else if focused == ui.focused && fluid.valid(ui, focused) && !has_layout(ui, focused) {
		fluid.blur(ui)
		if compact && !modal {
			fluid.focus(ui, app.workspace_tabs[app.workspace_view])
		}
	}
}

centered_area :: proc(area: fluid.Pins, maximum_width: f32) -> fluid.Pins {
	inset := max(0, (fluid.width(area) - maximum_width) / 2)
	return {area.left + inset, area.top, area.right - inset, area.bottom}
}

select_workspace :: proc(app: ^Showcase, ui: ^fluid.UI, id: fluid.Element_ID) {
	for tab, view in app.workspace_tabs {
		if tab == id {
			app.workspace_view = view
			if view == .Notebook && app.notebook.window != nil {
				dock_notebook(&app.notebook, ui, app.notebook.side)
			}
			return
		}
	}
}

workspace_for_focus :: proc(app: ^Showcase, id: fluid.Element_ID) -> Maybe(Workspace_View) {
	for part in app.notebook.parts {
		if id == part { return .Notebook }
	}
	if id == app.notebook.save { return .Notebook }
	t := &app.telemetry
	for tile in t.tiles {
		if id == tile.button { return .Readings }
	}
	for part in ([]fluid.Element_ID{t.view_mode, t.latest, t.chart, t.archive, t.range_choice, t.compare_button, t.limit}) {
		if id == part { return .Readings }
	}
	for marker in app.forest.markers {
		if id == marker { return .Canopy }
	}
	if id == app.panels.card { return .Canopy }
	return nil
}

workspace_focus :: proc(app: ^Showcase) -> fluid.Element_ID {
	switch app.workspace_view {
	case .Canopy: return app.forest.markers[app.site]
	case .Readings: return app.telemetry.view_mode
	case .Notebook: return app.notebook.parts[.New]
	}
	unreachable()
}

has_layout :: proc(ui: ^fluid.UI, id: fluid.Element_ID) -> bool {
	pins := fluid.bounds(ui, id)
	return fluid.is_active(ui, id) && fluid.width(pins) > 0 && fluid.height(pins) > 0
}

showcase_key :: proc(state: rawptr, window: ^fluid.Window, event: fluid.Keyboard_Event) -> bool {
	if !event.down || event.key != .Escape { return false }
	app := cast(^Showcase)state
	if event.repeat { return true }
	if app.panels.settings_open || app.panels.card_open {
		press_station_panel(app, window.ui, app.panels.back)
	} else if app.compact && app.workspace_view != .Canopy {
		app.workspace_view = .Canopy
		app.focus_target = app.workspace_tabs[.Canopy]
	} else {
		return false
	}
	return true
}
