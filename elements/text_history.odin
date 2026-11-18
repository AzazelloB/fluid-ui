package elements

import fluid ".."

import "core:os"
import "core:strings"

@(private="package")
Edit_Group :: enum {Separate, Typing, Backspace, Delete}

@(private="package")
Editor_Snapshot :: struct {
	value: string,
	anchor, caret: int,
}

@(private="package")
Editor_History :: struct {
	undo, redo: [dynamic]Editor_Snapshot,
	proposed: Maybe(string),
	last_group: Edit_Group,
	last_at: u64,
}

@(private="package")
reset_history :: proc(history: ^Editor_History) {
	clear_snapshots(&history.undo)
	clear_snapshots(&history.redo)
	history.last_group = .Separate
}

@(private="package")
destroy_editor :: proc(editor: ^Editor) {
	clear_preedit(editor)
	reset_history(&editor.history)
	delete(editor.history.undo)
	delete(editor.history.redo)
}

@(private="file")
clear_snapshots :: proc(snapshots: ^[dynamic]Editor_Snapshot) {
	for snapshot in snapshots^ {
		delete(snapshot.value, os.heap_allocator())
	}
	clear(snapshots)
}

@(private="file")
push_snapshot :: proc(stack: ^[dynamic]Editor_Snapshot, snapshot: Editor_Snapshot) {
	HISTORY_LIMIT :: 64
	if stack.allocator.procedure == nil {
		stack.allocator = os.heap_allocator()
	}
	if len(stack^) == HISTORY_LIMIT {
		delete(stack^[0].value, os.heap_allocator())
		ordered_remove(stack, 0)
	}
	append(stack, snapshot)
}

@(private="file")
editor_snapshot :: proc(element: Control_View) -> Editor_Snapshot {
	editor := editor_for(element.control)
	return {strings.clone(element.label, os.heap_allocator()), editor.anchor, editor.caret}
}

@(private="package")
record_editor_edit :: proc(ui: ^fluid.UI, id: fluid.Element_ID, next: Editor_Snapshot, group: Edit_Group) {
	element := get_element(ui, id)
	editor := editor_for(element.control)
	now := fluid.monotonic_ns()
	coalesce := group != .Separate && group == editor.history.last_group &&
		now - editor.history.last_at < 750_000_000 && len(editor.history.undo) > 0
	previous: Editor_Snapshot
	if !coalesce {
		previous = editor_snapshot(element)
	}
	if editor = apply_editor_snapshot(ui, id, next); editor != nil {
		clear_snapshots(&editor.history.redo)
		editor.history.last_group = group
		editor.history.last_at = now
		if !coalesce {
			push_snapshot(&editor.history.undo, previous)
		}
	} else if !coalesce {
		delete(previous.value, os.heap_allocator())
	}
}

@(private="package")
restore_editor_edit :: proc(ui: ^fluid.UI, id: fluid.Element_ID, redo: bool) {
	element := get_element(ui, id)
	editor := editor_for(element.control)
	editor.history.last_group = .Separate
	source := redo ? &editor.history.redo : &editor.history.undo
	if len(source^) == 0 {
		return
	}
	previous := editor_snapshot(element)
	target := pop(source)
	if editor = apply_editor_snapshot(ui, id, target); editor != nil {
		destination := redo ? &editor.history.undo : &editor.history.redo
		push_snapshot(destination, previous)
	} else {
		if fluid.valid(ui, id) {
			element = get_element(ui, id)
			if editor = editor_for(element.control); editor != nil && element.label == previous.value {
				source = redo ? &editor.history.redo : &editor.history.undo
				push_snapshot(source, target)
				delete(previous.value, os.heap_allocator())
				return
			}
		}
		delete(previous.value, os.heap_allocator())
	}
	delete(target.value, os.heap_allocator())
}
