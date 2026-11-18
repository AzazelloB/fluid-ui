package fluid

import "core:mem"
import "core:os"
import "core:slice"

// Bindings are owned by their element. Callback owners must stay at a stable
// address while bound. Public registration keeps the owner type.
Element_Callback :: struct($Argument: typeid) {
	data: rawptr,
	call: proc(data: rawptr, ui: ^UI, argument: Argument),
}

@(private="package")
Element_Binding :: struct($Owner, $Argument: typeid) {
	owner: ^Owner,
	run:   proc(owner: ^Owner, ui: ^UI, argument: Argument),
}

bind_element :: proc(callback: ^Element_Callback($Argument), owner: ^$Owner,
	run: proc(owner: ^Owner, ui: ^UI, argument: Argument),
) {
	assert(owner != nil && run != nil)
	binding := new(Element_Binding(Owner, Argument), os.heap_allocator())
	binding^ = {owner, run}
	clear_element_callback(callback)
	callback^ = {binding, proc(data: rawptr, ui: ^UI, argument: Argument) {
		binding := cast(^Element_Binding(Owner, Argument))data
		binding.run(binding.owner, ui, argument)
	}}
}

// Release a binding created by bind_element and reset the callback.
clear_element_callback :: proc(callback: ^Element_Callback($Argument)) {
	mem.free(callback.data, os.heap_allocator())
	callback^ = {}
}

on_press :: proc(ui: ^UI, id: Element_ID, owner: ^$Owner, run: proc(owner: ^Owner, ui: ^UI, id: Element_ID)) {
	bind_element(&get_element(ui, id).press, owner, run)
}

// Behavior runs only while this element is active, and ends on removal.
on_update :: proc(ui: ^UI, id: Element_ID, owner: ^$Owner, run: proc(owner: ^Owner, ui: ^UI, dt: f64)) {
	bind_element(&get_element(ui, id).update, owner, run)
}

@(private="package")
dispatch_behavior :: proc(ui: ^UI, dt: f64) {
	// Snapshot IDs: callbacks may remove elements, create windows, or navigate.
	active := slice.clone(ui.active[:], context.temp_allocator)
	events := slice.clone(ui.events[:], context.temp_allocator)
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
