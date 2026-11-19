package main

import fluid "../.."
import "../../elements"

Showcase :: struct {
	launch:        Launch_Reveal,
	pages:         fluid.Page_Set(Showcase),
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
	// Adding or removing a demo changes this list and its typed state field.
	definitions := [?]fluid.Page(Showcase){
		{title = "Rectangles", create = create_rectangles, leave = leave_rectangles},
		{title = "Transitions", create = create_conversations, leave = leave_conversations},
		{title = "Docking", create = create_docking, leave = leave_docking},
		{title = "Catalog", create = create_catalog, leave = leave_catalog},
		{title = "Controls", create = create_controls, leave = leave_controls},
		{title = "Logs", create = create_logs, leave = leave_logs},
		{title = "Bamboo Forest", create = create_bamboo, leave = leave_bamboo},
	}
	fluid.create_pages(&app.pages, ui, app, definitions[:])
	start_launch_reveal(&app.launch, ui.window)
	app.sidebar = elements.panel(ui.window, {}, {21, 29, 40, 255})
	create_title_bar(&app.title_bar, ui.window)
	for page, index in app.pages.entries {
		tab := elements.button(ui.window, {}, page.title, .Secondary)
		fluid.set_text_style(ui, tab, .Body, INK)
		fluid.bind_page_tab(&app.pages, index, tab)
	}
	update_navigation(app, ui, 0)
	fluid.on_update(ui, app.sidebar, app, update_navigation)
	fluid.open_page(&app.pages, 0)
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

navigation_width :: proc(app: ^Showcase, ui: ^fluid.UI) -> f32 {
	width := f32(11.25)
	for page in app.pages.entries {
		text_width, _ := fluid.measure_text(ui.window, page.title)
		width = max(width, text_width + 3.5)
	}
	return width
}

update_navigation :: proc(app: ^Showcase, ui: ^fluid.UI, dt: f64) {
	viewport := fluid.bounds(ui, ui.window.viewport)
	sidebar_right := navigation_width(app, ui)
	fluid.set_target(ui, app.sidebar, {right = sidebar_right, bottom = viewport.bottom})
	layout_title_bar(&app.title_bar, ui, viewport, sidebar_right)
	for page, index in app.pages.entries {
		fluid.set_target(ui, page.tab, tab_pins(sidebar_right, index))
	}
}
