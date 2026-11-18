package main

import "core:fmt"
import fluid "../.."
import "../../elements"

Controls :: struct {
	navigation: fluid.Element_ID,
	headings: [5]fluid.Element_ID,
	action, secondary, dangerous, action_feedback: fluid.Element_ID,
	toggle_label, toggle, options, select: fluid.Element_ID,
	number, price, pixels, number_hint, select_hint: fluid.Element_ID,
	name_label, name, notes_label, notes: fluid.Element_ID,
	action_count: int,
	action_pulse: f64,
}

create_controls :: proc(app: ^Showcase, ui: ^fluid.UI, entry: ^fluid.Page(Showcase)) {
	c := &app.controls
	c.navigation = app.sidebar
	scene := fluid.create_scene(ui.window)
	append(&entry.scenes, scene)

	for title, index in ([]string{"Actions", "Few values", "Many values", "Numbers", "Text values"}) {
		c.headings[index] = demo_text(scene, {}, title, .Heading, weight = .Bold)
	}

	c.action = elements.button(scene, {}, "Run")
	fluid.set_color(ui, c.action, {44, 78, 75, 255})
	c.secondary = elements.button(scene, {}, "Preview", .Secondary)
	c.dangerous = elements.dangerous_button(scene, {}, "Delete")
	fluid.set_color(ui, c.dangerous, {92, 49, 48, 255})
	c.action_feedback = demo_text(scene, {}, "Hold Delete or tap it three times.", .Caption, MUTED)
	for id in ([]fluid.Element_ID{c.action, c.secondary, c.dangerous}) {
		fluid.on_press(ui, id, c, run_control_action)
	}

	c.toggle_label = demo_text(scene, {}, "Crosshair")
	c.toggle = elements.toggle(scene, {}, "Off", false)
	c.options = elements.options(scene, {}, {"Small", "Medium", "Large"}, 1)
	c.select = elements.select(scene, {}, {
		"English", "Spanish", "French", "German", "Italian",
		"Portuguese", "Polish", "Ukrainian", "Japanese", "Korean",
	}, 0)

	c.select_hint = demo_text(scene, {}, "Click a neighbor or drag the current value.", .Caption, MUTED)
	c.number_hint = demo_text(scene, {}, "Drag to adjust. Double-click to type.", .Caption, MUTED)
	c.number = elements.number_input(scene, {}, 42)
	c.price = elements.number_input(scene, {}, 25, {minimum = 0, step = 0.25, prefix = "$"})
	c.pixels = elements.number_input(scene, {}, 16, {minimum = 0, maximum = 999, suffix = " px"})

	c.name_label = demo_text(scene, {}, "Name", .Body, MUTED)
	c.name = elements.text_input(scene, {}, "Alex", "Enter a name")
	fluid.set_draw(ui, c.name, demo_field_style)
	c.notes_label = demo_text(scene, {}, "Notes", .Body, MUTED)
	c.notes = elements.text_area(scene, {}, "First line\nSecond line", "Enter notes")
	fluid.set_draw(ui, c.notes, demo_field_style)

	for id in ([]fluid.Element_ID{
		c.toggle, c.options, c.select, c.number, c.price, c.pixels, c.name, c.notes,
	}) {
		elements.on_change(ui, id, c, apply_control_change)
	}

	fluid.on_update(ui, c.headings[0], c, update_controls)
	update_controls(c, ui, 0)
}

run_control_action :: proc(c: ^Controls, ui: ^fluid.UI, id: fluid.Element_ID) {
	c.action_count += 1
	c.action_pulse = 0.5
	action := id == c.action ? "Ran" : id == c.secondary ? "Previewed" : "Deleted"
	fluid.set_label(ui, c.action_feedback, fmt.tprintf("%s · %d", action, c.action_count))
}

apply_control_change :: proc(c: ^Controls, ui: ^fluid.UI, change: elements.Control_Change) {
	id := change.id
	switch value in change.value {
	case bool:
		fluid.set_selected(ui, id, value)
		fluid.set_label(ui, id, value ? "On" : "Off")
	case int: elements.set_choice(ui, id, value)
	case f64: elements.set_number(ui, id, value)
	case string: elements.set_text_value(ui, id, value)
	}
}

update_controls :: proc(c: ^Controls, ui: ^fluid.UI, dt: f64) {
	if c.action_pulse > 0 {
		c.action_pulse = max(0, c.action_pulse - dt)
		t := f32(c.action_pulse / 0.5)
		color := fluid.Color{
			u8(f32(MUTED.r) + (f32(INK.r) - f32(MUTED.r)) * t),
			u8(f32(MUTED.g) + (f32(INK.g) - f32(MUTED.g)) * t),
			u8(f32(MUTED.b) + (f32(INK.b) - f32(MUTED.b)) * t),
			MUTED.a,
		}
		fluid.set_text_style(ui, c.action_feedback, .Caption, color, .Left)
	}
	viewport := showcase_body(ui)
	content := content_pins(ui, c.navigation, viewport)
	x, y := content.left, content.top
	w := fluid.width(content)
	gap := f32(1.75)
	left_width := (w - gap) * 0.56
	right := x + left_width + gap
	right_width := content.right - right
	row_height :: 2.25

	for heading, index in c.headings {
		column_x := index < 3 ? x : right
		column_width := index < 3 ? left_width : right_width
		// Column rows leave room for the direct controls and their short hints.
		rows := [5]f32{0, 7, 16, 0, 8}
		fluid.set_layout(ui, heading, fluid.rect(column_x, y + rows[index], column_width, 1.75))
	}

	fluid.set_layout(ui, c.action, fluid.rect(x, y + 2.25, 4.25, row_height))
	fluid.set_layout(ui, c.secondary, fluid.rect(x + 4.65, y + 2.25, 5.5, row_height))
	fluid.set_layout(ui, c.dangerous, fluid.rect(x + 10.55, y + 2.25, 5, row_height))
	fluid.set_layout(ui, c.action_feedback, fluid.rect(x, y + 4.75, left_width, 1.25))
	fluid.set_layout(ui, c.toggle_label, fluid.rect(x, y + 9.25, 5.5, row_height))
	fluid.set_layout(ui, c.toggle, fluid.rect(x + 5.5, y + 9.25, 3.25, row_height))
	fluid.set_layout(ui, c.options, fluid.rect(x, y + 12.1, min(left_width, elements.control_width(ui, c.options)), row_height))
	fluid.set_layout(ui, c.select, fluid.rect(x, y + 18.25, min(left_width, elements.control_width(ui, c.select)), row_height))

	fluid.set_layout(ui, c.select_hint, fluid.rect(x, y + 20.75, left_width, 1.25))
	fluid.set_layout(ui, c.number_hint, fluid.rect(right, y + 4.75, right_width, 1.25))
	next_x := right
	for id in ([]fluid.Element_ID{c.number, c.price, c.pixels}) {
		available := (content.right - next_x) / f32(id == c.number ? 3 : id == c.price ? 2 : 1)
		size := min(available - 0.375, elements.control_width(ui, id))
		fluid.set_layout(ui, id, fluid.rect(next_x, y + 2.25, size, row_height))
		next_x += size + 0.375
	}

	fluid.set_layout(ui, c.name_label, fluid.rect(right, y + 10, right_width, 1.25))
	fluid.set_layout(ui, c.name, fluid.rect(right, y + 11.5, right_width, row_height))
	fluid.set_layout(ui, c.notes_label, fluid.rect(right, y + 14, right_width, 1.25))
	fluid.set_layout(ui, c.notes, fluid.rect(right, y + 15.5, right_width, 3.75))
}
