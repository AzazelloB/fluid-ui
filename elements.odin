package fluid

import "core:os"
import "core:slice"
import "core:strings"

Element_Definition :: struct {
	pins: Pins,
	label: string,
	color: Color,
	style: Style,
	surface, pressable, focusable, draggable: bool,
	cursor: Cursor,
	behavior: Element_Behavior,
	draw: Element_Draw,
}

@(private="package")
Element_Appearance :: struct {
	surface:       bool,
	color:         Color,
	label:         string,
	style:         Style,
	text_size:     f32,
	text_align:    Text_Align,
	text_weight:   Text_Weight,
	text_wrap:     bool,
	text_color:    Maybe(Color),
	text:          ^Text,
}

@(private="package")
element_appearance :: proc(app: ^UI, id: Element_ID) -> ^Element_Appearance {
	appearance, found := &app.appearances[id]
	return found ? appearance : nil
}

@(private="package")
ensure_appearance :: proc(app: ^UI, id: Element_ID) -> ^Element_Appearance {
	_, appearance, inserted, err := map_entry(&app.appearances, id)
	assert(err == nil)
	if inserted {
		appearance.text_size = 1
	}
	return appearance
}

@(private="file")
remove_appearance :: proc(app: ^UI, id: Element_ID) {
	if appearance := element_appearance(app, id); appearance != nil {
		release_cached_text(&appearance.text)
		delete(appearance.label, os.heap_allocator())
		delete_key(&app.appearances, id)
	}
}

// The engine owns the element and copies its label. An attached behavior can
// supply its own state, event handling, and resource cleanup.
create_element :: proc(window: ^Window, definition: Element_Definition) -> Element_ID {
	assert(window.open && !window.closing, "Cannot create elements in a closing or closed window")
	app := window.ui
	element := Element{
		window = window,
		pins = checked_pins(definition.pins),
		pressable = definition.pressable,
		focusable = definition.focusable,
		draggable = definition.draggable,
		cursor = definition.cursor,
		behavior = definition.behavior,
		draw = definition.draw,
	}
	app.next_draw_order += 1
	element.draw_order = app.next_draw_order
	id := register_element(app, element)
	if definition.surface || definition.label != "" || definition.color != {} || definition.style != {} {
		appearance := ensure_appearance(app, id)
		appearance.label = strings.clone(definition.label, os.heap_allocator())
		appearance.color = definition.color
		appearance.style = definition.style
		appearance.surface = definition.surface
	}
	append(&app.order, id)
	return id
}

// Retains a copy for the element, even if text came from a temporary allocator.
set_label :: proc(app: ^UI, id: Element_ID, text: string) {
	assert(valid(app, id))
	appearance := element_appearance(app, id)
	if appearance == nil {
		if text == "" {
			return
		}
		appearance = ensure_appearance(app, id)
	}
	if appearance.label == text {
		return
	}
	previous := appearance.label
	appearance.label = strings.clone(text, os.heap_allocator())
	update_cached_text(&appearance.text, appearance.label)
	delete(previous, os.heap_allocator())
}

// Invalidate the ID before recycling its slot. Other elements store values.
remove :: proc(app: ^UI, id: Element_ID) {
	if element_removing(app, id) {
		return
	}
	assert(valid(app, id), "Invalid or expired element reference")
	append(&app.removing, id)
	defer pop(&app.removing)
	remove_id(&app.order, id)
	remove_id(&app.hidden, id)
	remove_update(app, id)
	clear_element_input(app, id)
	release_element_text(app, id)
	behavior := element_behavior(app, id)
	if behavior.destroy != nil {
		behavior.destroy(behavior.state)
	}
	remove_appearance(app, id)
	// A cleanup callback can grow the registry. Resolve the ID again.
	element := get_element(app, id)
	clear_element_callback(&element.press)
	clear_element_callback(&element.update)
	_ = take_element_motion(app, id)
	generation := element.generation + 1
	element^ = Element{generation = generation}
	append(&app.free_elements, slot(id))
}

@(private="package")
element_removing :: proc(app: ^UI, id: Element_ID) -> bool {
	return slice.contains(app.removing[:], id)
}

// Remove live elements from the supplied list, skipping expired and repeated IDs.
remove_all :: proc(app: ^UI, ids: []Element_ID) {
	for id in ids {
		if valid(app, id) {
			remove(app, id)
		}
	}
}

set_color :: proc(app: ^UI, id: Element_ID, color: Color) {
	assert(valid(app, id))
	ensure_appearance(app, id).color = color
}

set_layout :: proc(app: ^UI, id: Element_ID, pins: Pins) {
	element := get_element(app, id)
	element.pins = checked_pins(pins)
	_ = take_element_motion(app, id)
}

// Update numeric destination pins without restarting an in-flight animation.
set_target :: proc(app: ^UI, id: Element_ID, pins: Pins) {
	element := get_element(app, id)
	target := checked_pins(pins)
	if motion := element_motion(app, id); motion != nil {
		if motion.target != target {
			motion.target = target
			sample_motion(element, motion^)
		}
	} else {
		element.pins = target
	}
}

element_window :: proc(app: ^UI, id: Element_ID) -> ^Window {
	return get_element(app, id).window
}

set_style :: proc(app: ^UI, id: Element_ID, style: Style) {
	assert(valid(app, id))
	ensure_appearance(app, id).style = style
}

set_text_style :: proc(app: ^UI, id: Element_ID, size: f32 = 1,
	color: Maybe(Color) = nil, align: Text_Align = .Center,
	weight: Text_Weight = .Regular,
) {
	assert(valid(app, id))
	appearance := ensure_appearance(app, id)
	if appearance.text_size != size || appearance.text_weight != weight {
		release_element_text(app, id)
		appearance = element_appearance(app, id)
	}
	appearance.text_size = size
	appearance.text_color = color
	appearance.text_align = align
	appearance.text_weight = weight
}

// Wrapped text starts at the top of its bounds and is clipped to them.
set_text_wrap :: proc(app: ^UI, id: Element_ID, wrap: bool = true) {
	assert(valid(app, id))
	ensure_appearance(app, id).text_wrap = wrap
}

// Hidden elements keep their state and draw order, and pause input and updates.
set_hidden :: proc(app: ^UI, id: Element_ID, hidden: bool = true) {
	if element_removing(app, id) {
		return
	}
	element := get_element(app, id)
	assert(id != element.window.viewport)
	was_hidden := slice.contains(app.hidden[:], id)
	if was_hidden == hidden {
		return
	}
	if hidden {
		remove_id(&app.order, id)
		append(&app.hidden, id)
		remove_update(app, id)
		if motion := take_motion(&app.motions, id); motion.animation.sample != nil {
			append(&app.paused_motions, motion)
		}
		clear_element_input(app, id)
	} else {
		remove_id(&app.hidden, id)
		insert_in_draw_order(app, id, element.draw_order)
		if element.update.call != nil {
			append(&app.updates, id)
		}
		if motion := take_motion(&app.paused_motions, id); motion.animation.sample != nil {
			append(&app.motions, motion)
		}
	}
}

is_active :: proc(app: ^UI, id: Element_ID) -> bool {
	return slice.contains(app.order[:], id)
}

@(private="file")
insert_in_draw_order :: proc(app: ^UI, id: Element_ID, order: u64) {
	index := len(app.order)
	for index > 0 && get_element(app, app.order[index - 1]).draw_order > order {
		index -= 1
	}
	inject_at(&app.order, index, id)
}

@(private="package")
clear_element_input :: proc(app: ^UI, id: Element_ID) {
	detach_input(app, id)
	if app.hovered == id {
		app.hovered = NO_ELEMENT
	}
	if app.pressed == id {
		app.pressed = NO_ELEMENT
	}
	if app.drag.element == id {
		end_drag(app)
	}
}

bring_to_front :: proc(app: ^UI, id: Element_ID) {
	if !valid(app, id) || id == element_window(app, id).viewport {
		return
	}
	element := get_element(app, id)
	app.next_draw_order += 1
	element.draw_order = app.next_draw_order
	if is_active(app, id) {
		remove_id(&app.order, id)
		append(&app.order, id)
	}
}

@(private="package")
remove_id :: proc(ids: ^[dynamic]Element_ID, id: Element_ID) {
	for value, i in ids^ {
		if value == id {
			ordered_remove(ids, i)
			return
		}
	}
}
