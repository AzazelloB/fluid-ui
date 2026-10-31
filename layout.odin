package main

select_page :: proc(app: ^App, id: Element_ID) {
	if app.current_page >= 0 {
		app.elements[app.current_page].selected = false
	}
	app.current_page = int(id)
	app.elements[id].selected = true
}

// The demo is a flat list. Position and size references define its layout.
define_layout :: proc(app: ^App) {
	PADDING :: 12
	GAP :: 8
	menu_items := group(app)
	sidebar := panel(app,
		{at(0), at(0)},
		{
			max_of(menu_items, .Content_Width, padding = PADDING * 2, minimum = 200),
			relative(app.viewport, .Height),
		},
		{32, 35, 43, 255},
	)
	top := relative(sidebar, .Top, PADDING)
	pages := [?]string{"Overview", "Projects and workspaces", "Settings", "About"}
	for page in pages {
		item := button(app,
			{relative(sidebar, .Left, PADDING), top},
			{relative(sidebar, .Width, -PADDING * 2), at(40)},
			page, on_press = select_page,
		)
		include(app, menu_items, item)
		if app.current_page < 0 {
			select_page(app, item)
		}
		top = relative(item, .Bottom, GAP)
	}

	blue := draggable_panel(app,
		{at(240), at(80)}, {at(240), at(140)},
		{95, 160, 255, 255},
	)
	_ = draggable_panel(app,
		{at(520), relative(blue, .Top)},
		{at(180), at(160)}, {245, 155, 85, 255},
	)
}
