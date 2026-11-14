package main

import fluid "../.."

Showcase :: struct {
	launch:        Launch_Reveal,
	pages:         fluid.Page_Set(Showcase),
	navigation:    ^fluid.Scene,
	sidebar:       fluid.Element_ID,
	tabs:          [dynamic]fluid.Element_ID,
	rectangles:    Rectangles,
	conversations: Conversations,
	docking:       Docking,
}

create_showcase :: proc(app: ^Showcase, ui: ^fluid.UI) {
	// Adding or removing a demo changes this list and its typed state field.
	definitions := [?]fluid.Page(Showcase){
		{title = "Rectangles", create = create_rectangles},
		{title = "Transitions", create = create_conversations},
		{title = "Docking", create = create_docking, leave = leave_docking},
	}
	fluid.create_pages(&app.pages, ui, app, definitions[:])
	start_launch_reveal(&app.launch, ui.window)
	app.navigation = fluid.create_scene(ui.window)
	viewport := fluid.bounds(ui, ui.window.viewport)
	width := navigation_width(app, ui)
	app.sidebar = fluid.panel(app.navigation, {right = width, bottom = viewport.bottom}, {21, 29, 40, 255})
	app.tabs = make([dynamic]fluid.Element_ID)
	for &page, index in app.pages.entries {
		top := 1.5 + f32(index) * 3.375
		tab := fluid.button(app.navigation, {left = 0.75, top = top, right = width - 0.75, bottom = top + 2.875}, page.title)
		fluid.set_text_style(ui, tab, .Body, INK)
		fluid.bind_page_tab(&app.pages, index, tab)
		append(&app.tabs, tab)
	}
	fluid.on_update(ui, app.sidebar, app, update_navigation)
	fluid.activate(app.navigation)
	fluid.open_page(&app.pages, 0)
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
	for tab, index in app.tabs {
		top := 1.5 + f32(index) * 3.375
		fluid.set_target(ui, tab, {left = 0.75, top = top, right = width - 0.75, bottom = top + 2.875})
	}
}
