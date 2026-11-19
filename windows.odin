package fluid

import "core:fmt"
import "core:math"
import virtual "core:mem/virtual"

Window_Flag :: enum {Hidden, Borderless, Transparent, Custom_Title_Bar}
Window_Flags :: bit_set[Window_Flag]

Config :: struct {
	title:        cstring,
	size:         [2]f32,
	minimum_size: [2]f32,
	flags:        Window_Flags,
	background:   Maybe(Color),
}

// Window pointers expire on close. Transfer elements before closing
// their window to preserve their IDs; remaining IDs are invalidated on close.
Window :: struct {
	ui:               ^UI,
	viewport:         Element_ID,
	background:       Color,
	close_requested:  bool,
	effect:           Window_Effect,
	clip:             Maybe(Window_Circle),
	drawable_size:    [2]i32,
	renderer:         ^Renderer,
	platform:         Platform_Window,
	open:             bool,
	display_scale:    f32,
	coordinate_scale: f32,
	minimum_size:     [2]f32,
	custom_title_bar: bool,
	storage:          virtual.Arena,
}

create_window :: proc(app: ^UI, config: Config) -> ^Window {
	context.allocator = virtual.arena_allocator(&app.storage)
	window: ^Window
	if len(app.free_windows) > 0 {
		window = pop(&app.free_windows)
	} else {
		window = new(Window)
	}
	window^ = Window{
		ui = app, background = {17, 23, 32, 255}, minimum_size = config.minimum_size,
		custom_title_bar = .Custom_Title_Bar in config.flags,
	}
	if background, specified := config.background.?; specified {
		window.background = background
	}
	if err := virtual.arena_init_growing(&window.storage); err != nil {
		append(&app.free_windows, window)
		return nil
	}
	allocator := virtual.arena_allocator(&window.storage)
	success := false
	defer {
		if !success {
			virtual.arena_destroy(&window.storage)
			append(&app.free_windows, window)
		}
	}
	if !platform_create_window(window, config) {
		fmt.eprintln("Cannot create native window")
		return nil
	}
	defer {
		if !success {
			platform_destroy_window(window)
		}
	}
	surface, result := platform_create_surface(window, app.vulkan.instance)
	if result != .SUCCESS {
		fmt.eprintln("Cannot create Vulkan window surface:", result)
		return nil
	}
	window.renderer = new(Renderer, allocator)
	transparent := platform_clips_drawable && .Transparent in config.flags
	if !renderer_init(window.renderer, &app.vulkan, surface, transparent) {
		return nil
	}
	window.open = true
	window.viewport = register_element(app, Element{window = window})
	append(&app.windows, window)
	success = true
	if .Hidden in config.flags {
		sync_window_geometry(window)
	} else if !show_window(window) {
		close_window(window)
		return nil
	}
	return window
}

// Elements and graphics resources are released before the window closes.
// Transfer any elements you want to keep using before closing their window.
close_window :: proc(window: ^Window) {
	if !window.open {
		return
	}
	app := window.ui
	for index := len(app.order) - 1; index >= 0; index -= 1 {
		id := app.order[index]
		if element_window(app, id) == window {
			remove(app, id)
		}
	}
	cancel_window_effect(window)
	remove(app, window.viewport)
	window.open = false
	renderer_destroy(window.renderer)
	platform_destroy_window(window)
	virtual.arena_destroy(&window.storage)
	window.renderer = nil
	for value, i in app.windows {
		if value == window {
			ordered_remove(&app.windows, i)
			break
		}
	}
	if window == app.window {
		app.running = false
	}
	append(&app.free_windows, window)
}

window_position :: proc(window: ^Window) -> [2]f32 {
	return platform_window_position(window) / UI_UNIT_POINTS
}

pointer_position :: proc(window: ^Window) -> [2]f32 {
	mouse, _ := platform_mouse_state()
	return window_point(window, mouse / UI_UNIT_POINTS)
}

show_window :: proc(window: ^Window) -> bool {
	if !platform_show_window(window, true) {
		return false
	}
	sync_window_geometry(window)
	return true
}

hide_window :: proc(window: ^Window) -> bool {
	return platform_show_window(window, false)
}

Window_Action :: enum {Close, Minimize, Toggle_Maximize, Toggle_Fullscreen}
Window_State :: enum {Normal, Minimized, Maximized, Fullscreen}

// Returns false if the action is unavailable for the window.
// Close uses the deferred close path so the caller can finish processing input.
window_action :: proc(window: ^Window, action: Window_Action) -> bool {
	if !window.open || window.close_requested {
		return false
	}
	if action == .Close {
		window.close_requested = true
		return true
	}
	return platform_window_action(window, action)
}

window_state :: proc(window: ^Window) -> Window_State {
	return platform_window_state(window)
}

window_is_active :: proc(window: ^Window) -> bool {
	return platform_window_is_active(window)
}

// The topmost hit element determines the native role in a custom title bar.
// Maximize lets Windows identify a custom maximize button for Snap Layouts.
Window_Hit :: enum {Client, Drag, Maximize}

set_window_hit :: proc(ui: ^UI, id: Element_ID, hit: Window_Hit) {
	get_element(ui, id).window_hit = hit
}

@(private="package")
window_hit_at :: proc(window: ^Window, native_point: [2]f32) -> Window_Hit {
	if !window.custom_title_bar || !window.open || window.clip != nil {
		return .Client
	}
	if id := hit_test(window.ui, window, native_point / window_scale(window)); id != NO_ELEMENT {
		return get_element(window.ui, id).window_hit
	}
	return .Client
}

// Physical renderer pixels per UI unit.
pixel_scale :: proc(window: ^Window) -> f32 {
	return window.display_scale * UI_UNIT_POINTS
}

// Native client coordinates per UI unit.
window_scale :: proc(window: ^Window) -> f32 {
	return window.coordinate_scale * UI_UNIT_POINTS
}

// Convert between window-local UI units and shared desktop coordinates.
desktop_point :: proc(window: ^Window, point: [2]f32) -> [2]f32 {
	return window_position(window) + point * window.coordinate_scale
}

window_point :: proc(window: ^Window, point: [2]f32) -> [2]f32 {
	return (point - window_position(window)) / window.coordinate_scale
}

set_window_position :: proc(window: ^Window, position: [2]f32) -> bool {
	if !platform_set_window_position(window, {i32(position[0] * UI_UNIT_POINTS), i32(position[1] * UI_UNIT_POINTS)}) {
		return false
	}
	sync_window_geometry(window)
	return true
}

set_window_size :: proc(window: ^Window, size: [2]f32) -> bool {
	native_size := native_window_size(size, window.coordinate_scale)
	if !platform_set_window_size(window, native_size) {
		return false
	}
	sync_window_geometry(window)
	return true
}

@(private="package")
native_window_size :: proc(size: [2]f32, coordinate_scale: f32) -> [2]i32 {
	scale := coordinate_scale * UI_UNIT_POINTS
	return {i32(math.round(size[0] * scale)), i32(math.round(size[1] * scale))}
}

@(private="package")
sync_window_geometry :: proc(window: ^Window) {
	display_scale, coordinate_scale := platform_window_scales(window)
	if display_scale != window.display_scale {
		window.display_scale = display_scale
		release_window_text(window)
	}
	if coordinate_scale != window.coordinate_scale {
		window.coordinate_scale = coordinate_scale
		if window.clip != nil {
			_ = platform_set_window_clip(window, window.clip)
		}
	}
	size := platform_window_size(window)
	scale := window_scale(window)
	get_element(window.ui, window.viewport).pins = Pins{right = f32(size[0]) / scale, bottom = f32(size[1]) / scale}
	density := display_scale / coordinate_scale
	window.drawable_size = {i32(math.round(f32(size[0]) * density)), i32(math.round(f32(size[1]) * density))}
}

Window_Circle :: struct {
	center: [2]f32,
	radius: f32,
}

// The clip is specified in window-local UI units. Pass nil to clear it.
// Platforms that clip the drawable require a transparent window.
set_window_clip :: proc(window: ^Window, circle: Maybe(Window_Circle)) -> bool {
	assert(window.open)
	if shape, clipped := circle.?; clipped {
		assert(shape.radius >= 0)
		if platform_clips_drawable && !window.renderer.transparent {
			return false
		}
	}
	if !platform_set_window_clip(window, circle) {
		return false
	}
	window.clip = circle
	return true
}

// Move the actual element, keeping its ID and animation progress.
// Literal positions and animation origins are rebased to preserve screen space.
transfer :: proc(app: ^UI, id: Element_ID, destination: ^Window) {
	assert(destination.ui == app && destination.open)
	element := get_element(app, id)
	source := element.window
	assert(id != source.viewport)
	assert(source.open, "Transfer elements before closing their window")
	if source == destination {
		return
	}
	element.pins = transfer_pins(source, destination, element.pins)
	element.motion.from = transfer_pins(source, destination, element.motion.from)
	detach_input(app, id)
	release_element_text(element)
	element.window = destination
}

@(private="file")
transfer_pins :: proc(source, destination: ^Window, pins: Pins) -> Pins {
	origin := [2]f32{pins.left, pins.top}
	return translated(pins, window_point(destination, desktop_point(source, origin)) - origin)
}
