package main

import fluid "../.."

Rectangles :: struct {
	scene: ^fluid.Scene,
}

create_rectangles :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	page := &app.rectangles
	page.scene = fluid.create_scene(ui.window)
	append(&entry.scenes, page.scene)
	blue := fluid.draggable_panel(page.scene,
		{fluid.at(240), fluid.at(80)}, {fluid.at(240), fluid.at(140)}, {95, 160, 255, 255},
	)
	_ = fluid.draggable_panel(page.scene,
		{fluid.at(520), fluid.relative(blue, .Top)}, {fluid.at(180), fluid.at(160)}, {245, 155, 85, 255},
	)
}
