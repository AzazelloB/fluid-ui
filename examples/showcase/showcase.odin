package main

import fluid "../.."

Showcase :: struct {
	launch:        Launch_Reveal,
	pages:         fluid.Page_Set(Showcase),
	navigation:    ^fluid.Scene,
	sidebar:       fluid.Element_ID,
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
	items := fluid.group(ui)
	app.sidebar = fluid.panel(app.navigation,
		{fluid.at(0), fluid.at(0)},
		{fluid.max_of(items, .Content_Width, padding = 24, minimum = 180), fluid.relative(ui.window.viewport, .Height)},
		{21, 29, 40, 255},
	)
	top := fluid.relative(app.sidebar, .Top, 24)
	for &page, index in app.pages.entries {
		tab := fluid.button(app.navigation,
			{fluid.relative(app.sidebar, .Left, 12), top},
			{fluid.relative(app.sidebar, .Width, -24), fluid.at(46)}, page.title,
		)
		fluid.set_text_style(ui, tab, .Body, INK)
		fluid.bind_page_tab(&app.pages, index, tab)
		fluid.include(ui, items, tab)
		top = fluid.relative(tab, .Bottom, 8)
	}
	fluid.activate(app.navigation)
	fluid.open_page(&app.pages, 0)
}
