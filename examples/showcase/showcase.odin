package main

import fluid "../.."
import "../../elements"

Showcase_Tab :: enum {Rectangles, Transitions, Docking, Catalog, Controls, Logs, Bamboo}

Showcase_Page :: struct {
	title:  string,
	create: proc(app: ^Showcase, ui: ^fluid.UI),
	leave:  proc(app: ^Showcase, ui: ^fluid.UI),
}

showcase_pages := [Showcase_Tab]Showcase_Page{
	.Rectangles = {title = "Rectangles", create = create_rectangles, leave = leave_rectangles},
	.Transitions = {title = "Transitions", create = create_conversations, leave = leave_conversations},
	.Docking = {title = "Docking", create = create_docking, leave = leave_docking},
	.Catalog = {title = "Catalog", create = create_catalog, leave = leave_catalog},
	.Controls = {title = "Controls", create = create_controls, leave = leave_controls},
	.Logs = {title = "Logs", create = create_logs, leave = leave_logs},
	.Bamboo = {title = "Bamboo Forest", create = create_bamboo, leave = leave_bamboo},
}

Showcase :: struct {
	launch:        Launch_Reveal,
	tabs:          [Showcase_Tab]fluid.Element_ID,
	current_page:  Maybe(Showcase_Tab),
	sidebar:       fluid.Element_ID,
	title_bar:     Title_Bar,
	rectangles:    Rectangles,
	conversations: Conversations,
	docking:       Docking,
	catalog:       Catalog,
	controls:      Controls,
	logs:          Logs,
	bamboo:        Bamboo,
}

create_showcase :: proc(app: ^Showcase, ui: ^fluid.UI) {
	start_launch_reveal(&app.launch, ui.window)
	app.sidebar = elements.panel(ui.window, {}, {21, 29, 40, 255})
	create_title_bar(&app.title_bar, ui.window)
	for page, index in showcase_pages {
		tab := elements.button(ui.window, {}, page.title, .Secondary)
		fluid.set_text_style(ui, tab, .Body, INK)
		app.tabs[index] = tab
		fluid.on_press(ui, tab, app, select_tab)
	}
	update_navigation(app, ui, 0)
	fluid.on_update(ui, app.sidebar, app, update_navigation)
	select_tab(app, ui, app.tabs[.Rectangles])
}

select_tab :: proc(app: ^Showcase, ui: ^fluid.UI, id: fluid.Element_ID) {
	for tab, index in app.tabs {
		if tab != id || app.current_page == index {
			continue
		}
		if previous, open := app.current_page.?; open {
			showcase_pages[previous].leave(app, ui)
			fluid.set_selected(ui, app.tabs[previous], false)
		}
		showcase_pages[index].create(app, ui)
		app.current_page = index
		fluid.set_selected(ui, tab, true)
		return
	}
}

showcase_body :: proc(ui: ^fluid.UI) -> fluid.Pins {
	viewport := fluid.bounds(ui, ui.window.viewport)
	viewport.top = min(TITLE_BAR_HEIGHT, viewport.bottom)
	return viewport
}

content_pins :: proc(ui: ^fluid.UI, sidebar: fluid.Element_ID, viewport: fluid.Pins) -> fluid.Pins {
	return {
		left = fluid.bounds(ui, sidebar).right + 2.25,
		top = viewport.top + 1.5,
		right = viewport.right - 2.25,
		bottom = viewport.bottom - 1.5,
	}
}

tab_pins :: proc(sidebar_right: f32, index: int) -> fluid.Pins {
	top := TITLE_BAR_HEIGHT + 1.5 + f32(index) * 3.375
	return {left = 0.75, top = top, right = sidebar_right - 0.75, bottom = top + 2.875}
}

navigation_width :: proc(ui: ^fluid.UI) -> f32 {
	width := f32(11.25)
	for page in showcase_pages {
		text_width, _ := fluid.measure_text(ui.window, page.title)
		width = max(width, text_width + 3.5)
	}
	return width
}

update_navigation :: proc(app: ^Showcase, ui: ^fluid.UI, dt: f64) {
	viewport := fluid.bounds(ui, ui.window.viewport)
	sidebar_right := navigation_width(ui)
	fluid.set_target(ui, app.sidebar, {right = sidebar_right, bottom = viewport.bottom})
	layout_title_bar(&app.title_bar, ui, viewport, sidebar_right)
	for tab, index in app.tabs {
		fluid.set_target(ui, tab, tab_pins(sidebar_right, int(index)))
	}
}
