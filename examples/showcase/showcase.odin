package main

import fluid "../.."

Page :: enum {Rectangles, Conversations, Docking}
Showcase :: struct {
	navigation:    ^fluid.Scene,
	sidebar:       fluid.Element_ID,
	tabs:          [Page]fluid.Element_ID,
	current:       Maybe(Page),
	rectangles:    Rectangles,
	conversations: Conversations,
	docking:       Docking,
}

create_showcase :: proc(app: ^Showcase, ui: ^fluid.UI) {
	app.navigation = fluid.create_scene(ui.window)
	items := fluid.group(ui)
	app.sidebar = fluid.panel(app.navigation,
		{fluid.at(0), fluid.at(0)},
		{fluid.max_of(items, .Content_Width, padding = 24, minimum = 200), fluid.relative(ui.window.viewport, .Height)},
		{32, 35, 43, 255},
	)
	top := fluid.relative(app.sidebar, .Top, 12)
	names := [?]string{"Rectangles", "Fluid transition", "Dock & detach"}
	for name, i in names {
		tab := fluid.button(app.navigation,
			{fluid.relative(app.sidebar, .Left, 12), top},
			{fluid.relative(app.sidebar, .Width, -24), fluid.at(40)}, name,
		)
		app.tabs[Page(i)] = tab
		fluid.include(ui, items, tab)
		top = fluid.relative(tab, .Bottom, 8)
	}
	fluid.activate(app.navigation)
	open_page(app, ui, .Rectangles)
}

open_page :: proc(app: ^Showcase, ui: ^fluid.UI, page: Page) {
	if previous, exists := app.current.?; exists {
		if previous == page {
			return
		}
		fluid.set_selected(ui, app.tabs[previous], false)
		switch previous {
		case .Rectangles:
			fluid.deactivate(app.rectangles.scene)
		case .Conversations:
			fluid.deactivate(app.conversations.scene)
		case .Docking:
			deactivate_docking(&app.docking, ui)
		}
	}
	app.current = page
	fluid.set_selected(ui, app.tabs[page], true)
	switch page {
	case .Rectangles:
		if app.rectangles.scene == nil {
			create_rectangles(&app.rectangles, ui)
		}
		fluid.activate(app.rectangles.scene)
	case .Conversations:
		if app.conversations.scene == nil {
			create_conversations(&app.conversations, ui, app.sidebar)
		}
		fluid.activate(app.conversations.scene)
	case .Docking:
		if app.docking.scene == nil {
			create_docking(&app.docking, ui, app.sidebar)
		}
		activate_docking(&app.docking)
	}
}

update_showcase :: proc(app: ^Showcase, ui: ^fluid.UI) {
	for page in Page {
		if fluid.pressed(ui, app.tabs[page]) {
			open_page(app, ui, page)
		}
	}
	if current, exists := app.current.?; exists {
		switch current {
		case .Rectangles:
		case .Conversations:
			update_conversations(&app.conversations, ui)
		case .Docking:
			update_docking(&app.docking, ui)
		}
	}
}
