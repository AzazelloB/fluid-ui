package fluid

import virtual "core:mem/virtual"

// Bindings live in UI storage. The owner must remain at a stable address until
// its elements are removed (or the UI is destroyed). Public callbacks stay typed.
@(private="package")
Element_Callback :: struct {
	data: rawptr,
	call: proc(data: rawptr, ui: ^UI, id: Element_ID),
}

@(private="package")
Element_Binding :: struct($Owner: typeid) {
	owner: ^Owner,
	run:   proc(owner: ^Owner, ui: ^UI, id: Element_ID),
}

@(private="package")
bind_element :: proc(ui: ^UI, owner: ^$Owner, run: proc(owner: ^Owner, ui: ^UI, id: Element_ID)) -> Element_Callback {
	assert(owner != nil && run != nil)
	context.allocator = virtual.arena_allocator(&ui.storage)
	binding := new(Element_Binding(Owner))
	binding^ = {owner, run}
	return {binding, proc(data: rawptr, ui: ^UI, id: Element_ID) {
		binding := cast(^Element_Binding(Owner))data
		binding.run(binding.owner, ui, id)
	}}
}

on_press :: proc(ui: ^UI, id: Element_ID, owner: ^$Owner, run: proc(owner: ^Owner, ui: ^UI, id: Element_ID)) {
	get_element(ui, id).press = bind_element(ui, owner, run)
}

@(private="package")
Update_Callback :: struct {
	data: rawptr,
	call: proc(data: rawptr, ui: ^UI, dt: f64),
}

@(private="package")
Update_Binding :: struct($Owner: typeid) {
	owner: ^Owner,
	run:   proc(owner: ^Owner, ui: ^UI, dt: f64),
}

// Behavior runs only while this element is active, and ends on removal.
on_update :: proc(ui: ^UI, id: Element_ID, owner: ^$Owner, run: proc(owner: ^Owner, ui: ^UI, dt: f64)) {
	assert(owner != nil && run != nil)
	context.allocator = virtual.arena_allocator(&ui.storage)
	binding := new(Update_Binding(Owner))
	binding^ = {owner, run}
	get_element(ui, id).update = {binding, proc(data: rawptr, ui: ^UI, dt: f64) {
		binding := cast(^Update_Binding(Owner))data
		binding.run(binding.owner, ui, dt)
	}}
}

@(private="package")
dispatch_behavior :: proc(ui: ^UI, dt: f64) {
	// Snapshot IDs: callbacks may remove elements, create windows, or navigate.
	active := make([]Element_ID, len(ui.active), context.temp_allocator)
	copy(active, ui.active[:])
	events := make([]Element_ID, len(ui.events), context.temp_allocator)
	copy(events, ui.events[:])
	for id in events {
		if !is_active(ui, id) {
			continue
		}
		callback := get_element(ui, id).press
		if callback.call != nil {
			callback.call(callback.data, ui, id)
		}
		if !ui.running {
			return
		}
	}
	for id in active {
		if !is_active(ui, id) {
			continue
		}
		callback := get_element(ui, id).update
		if callback.call != nil {
			callback.call(callback.data, ui, dt)
		}
		if !ui.running {
			return
		}
	}
}
