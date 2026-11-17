package fluid

import "core:mem"
import "core:os"
import "vendor:sdl3"

@(private="package")
Window_Effect :: struct {
	data:              rawptr,
	draw:              proc(data: rawptr, window: ^Window, progress: f32),
	complete:          proc(data: rawptr, window: ^Window),
	elapsed, duration: f64,
	started:           bool,
	frame:             u64,
}

@(private="package")
Effect_Binding :: struct($Owner: typeid) {
	owner:    ^Owner,
	draw:     proc(owner: ^Owner, window: ^Window, progress: f32),
	complete: proc(owner: ^Owner, window: ^Window),
}

// One compositing effect per window. Fluid owns its clock and removes it before
// completion. Closing the window cancels it. Drawing must not close the window.
window_effect :: proc(window: ^Window, duration: f64, owner: ^$Owner,
	draw: proc(owner: ^Owner, window: ^Window, progress: f32),
	complete: proc(owner: ^Owner, window: ^Window) = nil,
) {
	assert(window.handle != nil && duration > 0 && owner != nil && draw != nil)
	binding := new(Effect_Binding(Owner), os.heap_allocator())
	binding^ = {owner, draw, complete}
	cancel_window_effect(window)
	window.effect = Window_Effect{
		data = binding, duration = duration, frame = window.ui.frame,
		draw = proc(data: rawptr, window: ^Window, progress: f32) {
			binding := cast(^Effect_Binding(Owner))data
			binding.draw(binding.owner, window, progress)
		},
		complete = proc(data: rawptr, window: ^Window) {
			binding := cast(^Effect_Binding(Owner))data
			if binding.complete != nil {
				binding.complete(binding.owner, window)
			}
		},
	}
}

cancel_window_effect :: proc(window: ^Window) {
	mem.free(window.effect.data, os.heap_allocator())
	window.effect = {}
}

@(private="package")
advance_window_effects :: proc(ui: ^UI, dt: f64) {
	// Window callbacks can close/create windows. Viewport IDs guard recycled slots.
	viewports := make([]Element_ID, len(ui.windows), context.temp_allocator)
	for window, i in ui.windows {
		viewports[i] = window.viewport
	}
	for id in viewports {
		if !ui.running {
			return
		}
		if !valid(ui, id) {
			continue
		}
		window := element_window(ui, id)
		effect := &window.effect
		if effect.draw == nil || effect.frame == ui.frame || .HIDDEN in sdl3.GetWindowFlags(window.handle) {
			continue
		}
		if !effect.started {
			effect.started = true
		} else {
			effect.elapsed = min(effect.duration, effect.elapsed + max(dt, 0))
		}
		if effect.elapsed >= effect.duration {
			finished := effect^
			effect^ = {}
			finished.complete(finished.data, window)
			mem.free(finished.data, os.heap_allocator())
		}
	}
}

@(private="package")
present_window :: proc(window: ^Window) {
	draw(window.ui, window)
	effect := window.effect
	if effect.draw != nil {
		effect.draw(effect.data, window, f32(effect.elapsed / effect.duration))
	}
	sdl3.RenderPresent(window.renderer)
}
