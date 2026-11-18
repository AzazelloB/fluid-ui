package main

import fluid "../.."
import "../../elements"

Showcase :: struct {
	launch:        Launch_Reveal,
	pages:         fluid.Page_Set(Showcase),
	sidebar:       fluid.Element_ID,
	rectangles:    Rectangles,
	conversations: Conversations,
	docking:       Docking,
	catalog:       Catalog,
	controls:      Controls,
	logs:          Logs,
}

create_showcase :: proc(app: ^Showcase, ui: ^fluid.UI) {
	// Adding or removing a demo changes this list and its typed state field.
	definitions := [?]fluid.Page(Showcase){
		{title = "Rectangles", create = create_rectangles},
		{title = "Transitions", create = create_conversations},
		{title = "Docking", create = create_docking, leave = leave_docking},
		{title = "Catalog", create = create_catalog, leave = leave_catalog},
		{title = "Controls", create = create_controls},
		{title = "Logs", create = create_logs},
	}
	fluid.create_pages(&app.pages, ui, app, definitions[:])
	start_launch_reveal(&app.launch, ui.window)
	navigation := fluid.create_scene(ui.window)
	viewport := fluid.bounds(ui, ui.window.viewport)
	width := navigation_width(app, ui)
	app.sidebar = elements.panel(navigation, {right = width, bottom = viewport.bottom}, {21, 29, 40, 255})
	for page, index in app.pages.entries {
		tab := elements.button(navigation, tab_pins(width, index), page.title, .Secondary)
		fluid.set_text_style(ui, tab, .Body, INK)
		fluid.bind_page_tab(&app.pages, index, tab)
	}
	fluid.on_update(ui, app.sidebar, app, update_navigation)
	fluid.activate(navigation)
	fluid.open_page(&app.pages, 0)
}

// The inset content area starts beside the navigation sidebar.
content_pins :: proc(ui: ^fluid.UI, sidebar: fluid.Element_ID, viewport: fluid.Pins) -> fluid.Pins {
	return {
		left = fluid.bounds(ui, sidebar).right + 2.25,
		top = 1.5,
		right = viewport.right - 2.25,
		bottom = viewport.bottom - 1.5,
	}
}

tab_pins :: proc(width: f32, index: int) -> fluid.Pins {
	top := 1.5 + f32(index) * 3.375
	return {left = 0.75, top = top, right = width - 0.75, bottom = top + 2.875}
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
	width := navigation_width(app, ui)
	fluid.set_target(ui, app.sidebar, {right = width, bottom = viewport.bottom})
	for page, index in app.pages.entries {
		fluid.set_target(ui, page.tab, tab_pins(width, index))
	}
}
