package fluid

import "core:mem"
import "core:os"

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
	element := get_element(ui, id)
	if element.update.call == nil && is_active(ui, id) {
		append(&ui.updates, id)
	}
	bind_element(&element.update, owner, run)
}

@(private="package")
remove_update :: proc(ui: ^UI, id: Element_ID) {
	remove_id(&ui.updates, id)
	remove_id(&ui.frame_updates, id)
}

@(private="package")
dispatch_updates :: proc(ui: ^UI, dt: f64) {
	// Reverse the update IDs so popping preserves their registration order.
	// Hiding or removing an element also removes its remaining frame work.
	defer clear(&ui.frame_updates)
	for index := len(ui.updates) - 1; index >= 0; index -= 1 {
		append(&ui.frame_updates, ui.updates[index])
	}
	for ui.running && len(ui.frame_updates) > 0 {
		id := pop(&ui.frame_updates)
		callback := get_element(ui, id).update
		callback.call(callback.data, ui, dt)
	}
}
