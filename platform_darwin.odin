#+build darwin
package fluid

import "base:intrinsics"
import "base:runtime"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import objc "core:sys/darwin/ObjectiveC"
import AppKit "vendor:darwin/AppKit"
import CA "vendor:darwin/QuartzCore"
import vk "vendor:vulkan"

// Use the Objective-C library already linked by Odin's Darwin runtime.
@(private="file", default_calling_convention="c")
foreign _ {
	objc_getClass :: proc(name: cstring) -> objc.Class ---
	objc_allocateClassPair :: proc(superclass: objc.Class, name: cstring, extraBytes: uint) -> objc.Class ---
	objc_registerClassPair :: proc(cls: objc.Class) ---
	objc_disposeClassPair :: proc(cls: objc.Class) ---
	objc_getProtocol :: proc(name: cstring) -> ^objc.Protocol ---
	sel_registerName :: proc(name: cstring) -> objc.SEL ---
	class_addMethod :: proc(cls: objc.Class, name: objc.SEL, imp: objc.IMP, types: cstring) -> objc.BOOL ---
	class_addProtocol :: proc(cls: objc.Class, protocol: ^objc.Protocol) -> objc.BOOL ---
	class_addIvar :: proc(cls: objc.Class, name: cstring, size: uint, alignment: u8, types: cstring) -> objc.BOOL ---
	object_getInstanceVariable :: proc(obj: objc.id, name: cstring, outValue: ^rawptr) -> objc.Ivar ---
	object_setInstanceVariable :: proc(obj: objc.id, name: cstring, value: rawptr) -> objc.Ivar ---
}

@(private="package")
Platform_Window :: struct {
	handle:     ^AppKit.Window,
	view:       objc.id,
	layer:      ^CA.MetalLayer,
	text_input: bool,
	ime_area:   [4]i32,
	marked:     ^NS.String,
	selection:  NS.Range,
	clip_active: bool,
	live_resize_timer: objc.id,
	zoom_pending: bool,
	title_bar_down: ^AppKit.Event,
}

@(objc_class="NSObject", private="file")
Mac_Object :: struct {using _: intrinsics.objc_object}

@(private="file")
mac_receiver :: proc "contextless" (obj: rawptr) -> ^Mac_Object {
	return cast(^Mac_Object)obj
}

@(private="package")
platform_surface_extension : cstring : "VK_EXT_metal_surface"

@(private="file")
mac_send :: intrinsics.objc_send
@(private="file")
mac_application: ^AppKit.Application
@(private="file")
mac_delegate: objc.id
@(private="file")
mac_view_class: objc.Class
@(private="file")
mac_delegate_class: objc.Class
@(private="file")
mac_borderless_class: objc.Class
@(private="file")
mac_events: [dynamic]Platform_Event
@(private="file")
mac_event_index: int

@(private="package")
platform_init :: proc() -> bool {
	// The scoped helper drains the pool at scope exit.
	NS.scoped_autoreleasepool()
	if !mac_register_classes() {
		return false
	}
	mac_events = make([dynamic]Platform_Event, 0, 32)
	mac_application = AppKit.Application.sharedApplication()
	mac_delegate = mac_send(objc.id, mac_receiver(mac_delegate_class), "new")
	mac_send(nil, mac_receiver(mac_application), "setDelegate:", mac_delegate)
	mac_application->setActivationPolicy(.Regular)
	mac_install_menu()
	mac_application->finishLaunching()
	return true
}

@(private="package")
platform_shutdown :: proc() {
	mac_send(nil, mac_receiver(mac_application), "setDelegate:", objc.id(nil))
	mac_send(nil, mac_receiver(mac_delegate), "release")
	mac_application = nil
	mac_delegate = nil
	delete(mac_events)
	mac_events = nil
	mac_event_index = 0
}

@(private="file")
mac_install_menu :: proc() {
	menu := mac_send(objc.id, mac_receiver(objc_getClass("NSMenu")), "new")
	item := mac_send(objc.id, mac_receiver(objc_getClass("NSMenuItem")), "new")
	submenu := mac_send(objc.id, mac_receiver(objc_getClass("NSMenu")), "new")
	quit := mac_string("Quit")
	key := mac_string("q")
	mac_send(nil, mac_receiver(submenu), "addItemWithTitle:action:keyEquivalent:", quit, sel_registerName("terminate:"), key)
	mac_send(nil, mac_receiver(menu), "addItem:", item)
	mac_send(nil, mac_receiver(item), "setSubmenu:", submenu)
	mac_send(nil, mac_receiver(mac_application), "setMainMenu:", menu)
	mac_send(nil, mac_receiver(key), "release")
	mac_send(nil, mac_receiver(quit), "release")
	mac_send(nil, mac_receiver(submenu), "release")
	mac_send(nil, mac_receiver(item), "release")
	mac_send(nil, mac_receiver(menu), "release")
}

@(private="file")
mac_register_classes :: proc() -> bool {
	if mac_view_class != nil {
		return true
	}
	view := objc_allocateClassPair(objc_getClass("NSView"), "FluidContentView", 0)
	delegate := objc_allocateClassPair(objc_getClass("NSObject"), "FluidApplicationDelegate", 0)
	borderless := objc_allocateClassPair(objc_getClass("NSWindow"), "FluidBorderlessWindow", 0)
	if view == nil || delegate == nil || borderless == nil ||
	   !class_addIvar(view, "_fluidWindow", size_of(rawptr), 3, "^v") {
		classes := [?]objc.Class{view, delegate, borderless}
		for cls in classes {
			if cls != nil { objc_disposeClassPair(cls) }
		}
		return false
	}
	class_addProtocol(view, objc_getProtocol("NSTextInputClient"))
	mac_method(view, "acceptsFirstResponder", cast(objc.IMP)mac_view_accepts_first_responder, "B@:")
	mac_method(view, "keyDown:", cast(objc.IMP)mac_view_key_down, "v@:@")
	mac_method(view, "mouseExited:", cast(objc.IMP)mac_mouse_exited, "v@:@")
	mac_method(view, "windowShouldClose:", cast(objc.IMP)mac_window_should_close, "B@:@")
	mac_method(view, "windowDidResize:", cast(objc.IMP)mac_window_resized, "v@:@")
	mac_method(view, "windowWillStartLiveResize:", cast(objc.IMP)mac_window_live_resize_started, "v@:@")
	mac_method(view, "windowDidEndLiveResize:", cast(objc.IMP)mac_window_live_resize_ended, "v@:@")
	mac_method(view, "windowDidExitFullScreen:", cast(objc.IMP)mac_window_exited_fullscreen, "v@:@")
	mac_method(view, "fluidLiveResizeTick:", cast(objc.IMP)mac_live_resize_tick, "v@:@")
	mac_method(view, "windowDidChangeBackingProperties:", cast(objc.IMP)mac_window_resized, "v@:@")
	mac_method(view, "windowDidResignKey:", cast(objc.IMP)mac_window_resigned_key, "v@:@")
	mac_method(view, "insertText:replacementRange:", cast(objc.IMP)mac_insert_text, "v@:@{_NSRange=QQ}")
	mac_method(view, "setMarkedText:selectedRange:replacementRange:", cast(objc.IMP)mac_set_marked_text,
		"v@:@{_NSRange=QQ}{_NSRange=QQ}")
	mac_method(view, "unmarkText", cast(objc.IMP)mac_unmark_text, "v@:")
	mac_method(view, "hasMarkedText", cast(objc.IMP)mac_has_marked_text, "B@:")
	mac_method(view, "markedRange", cast(objc.IMP)mac_marked_range, "{_NSRange=QQ}@:")
	mac_method(view, "selectedRange", cast(objc.IMP)mac_selected_range, "{_NSRange=QQ}@:")
	mac_method(view, "validAttributesForMarkedText", cast(objc.IMP)mac_valid_attributes, "@@:")
	mac_method(view, "attributedSubstringForProposedRange:actualRange:", cast(objc.IMP)mac_attributed_substring,
		"@@:{_NSRange=QQ}^{_NSRange=QQ}")
	mac_method(view, "firstRectForCharacterRange:actualRange:", cast(objc.IMP)mac_character_rect,
		"{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}")
	mac_method(view, "characterIndexForPoint:", cast(objc.IMP)mac_character_index, "Q@:{CGPoint=dd}")
	mac_method(view, "doCommandBySelector:", cast(objc.IMP)mac_ignore_text_command, "v@::")
	mac_method(delegate, "applicationShouldTerminate:", cast(objc.IMP)mac_should_terminate, "Q@:@")
	mac_method(borderless, "canBecomeKeyWindow", cast(objc.IMP)mac_view_accepts_first_responder, "B@:")
	objc_registerClassPair(view)
	objc_registerClassPair(delegate)
	objc_registerClassPair(borderless)
	mac_view_class = view
	mac_delegate_class = delegate
	mac_borderless_class = borderless
	return true
}

@(private="file")
mac_method :: proc(class: objc.Class, name: cstring, method: objc.IMP, encoding: cstring) {
	added := class_addMethod(class, sel_registerName(name), method, encoding)
	assert(added)
}

@(private="package")
platform_create_window :: proc(window: ^Window, config: Config) -> bool {
	NS.scoped_autoreleasepool()
	style: AppKit.WindowStyleMask = {.Titled, .Closable, .Miniaturizable, .Resizable}
	class := objc_getClass("NSWindow")
	if window.custom_title_bar {
		style += {.FullSizeContentView}
	} else if .Borderless in config.flags {
		style = {}
		class = mac_borderless_class
	}
	bounds := NS.Rect{size = {
		max(1, f64(config.size[0]) * f64(UI_UNIT_POINTS)),
		max(1, f64(config.size[1]) * f64(UI_UNIT_POINTS)),
	}}
	handle := mac_send(^AppKit.Window, mac_receiver(class), "alloc")
	handle = mac_send(^AppKit.Window, mac_receiver(handle), "initWithContentRect:styleMask:backing:defer:",
		bounds, style, AppKit.BackingStoreType.Buffered, bool(false))
	if handle == nil {
		return false
	}
	mac_send(nil, mac_receiver(handle), "setReleasedWhenClosed:", bool(false))
	window.platform.handle = handle
	view := mac_send(objc.id, mac_receiver(mac_view_class), "alloc")
	view = mac_send(objc.id, mac_receiver(view), "initWithFrame:", bounds)
	layer := mac_send(^CA.MetalLayer, mac_receiver(objc_getClass("CAMetalLayer")), "layer")
	if view == nil || layer == nil {
		mac_send(nil, mac_receiver(view), "release")
		platform_destroy_window(window)
		return false
	}
	window.platform.view = view
	window.platform.layer = layer
	object_setInstanceVariable(view, "_fluidWindow", window)
	mac_send(nil, mac_receiver(view), "setLayer:", layer)
	mac_send(nil, mac_receiver(view), "setWantsLayer:", bool(true))
	mac_send(nil, mac_receiver(handle), "setContentView:", view)
	mac_send(nil, mac_receiver(handle), "setDelegate:", view)
	if window.custom_title_bar {
		mac_set_title_bar_hidden(handle, true)
		behavior := mac_send(AppKit.WindowCollectionBehavior, mac_receiver(handle), "collectionBehavior")
		mac_send(nil, mac_receiver(handle), "setCollectionBehavior:", behavior + {.FullScreenPrimary})
	}
	mac_send(nil, mac_receiver(handle), "makeFirstResponder:", view)
	mac_send(nil, mac_receiver(handle), "setAcceptsMouseMovedEvents:", bool(true))
	track := mac_send(objc.id, mac_receiver(objc_getClass("NSTrackingArea")), "alloc")
	track = mac_send(objc.id, mac_receiver(track), "initWithRect:options:owner:userInfo:", bounds,
		AppKit.TrackingAreaOptions{.MouseEnteredAndExited, .ActiveAlways, .InVisibleRect, .EnabledDuringMouseDrag},
		view, objc.id(nil))
	mac_send(nil, mac_receiver(view), "addTrackingArea:", track)
	mac_send(nil, mac_receiver(track), "release")
	if .Transparent in config.flags {
		mac_send(nil, mac_receiver(layer), "setOpaque:", bool(false))
		mac_send(nil, mac_receiver(handle), "setOpaque:", bool(false))
		transparent := mac_send(objc.id, mac_receiver(objc_getClass("NSColor")), "clearColor")
		mac_send(nil, mac_receiver(handle), "setBackgroundColor:", transparent)
	}
	title := mac_string(string(config.title))
	mac_send(nil, mac_receiver(handle), "setTitle:", title)
	mac_send(nil, mac_receiver(title), "release")
	minimum := NS.Size{
		max(1, f64(config.minimum_size[0]) * f64(UI_UNIT_POINTS)),
		max(1, f64(config.minimum_size[1]) * f64(UI_UNIT_POINTS)),
	}
	mac_send(nil, mac_receiver(handle), "setContentMinSize:", minimum)
	mac_send(nil, mac_receiver(handle), "center")
	mac_resize_layer(window)
	return true
}

@(private="package")
platform_destroy_window :: proc(window: ^Window) {
	NS.scoped_autoreleasepool()
	handle := window.platform.handle
	if handle == nil {
		return
	}
	mac_stop_live_resize(window)
	mac_clear_title_bar_press(window)
	mac_send(nil, mac_receiver(handle), "setDelegate:", objc.id(nil))
	mac_send(nil, mac_receiver(handle), "close")
	mac_send(nil, mac_receiver(window.platform.marked), "release")
	mac_send(nil, mac_receiver(window.platform.view), "release")
	mac_send(nil, mac_receiver(handle), "release")
	for i := len(mac_events) - 1; i >= mac_event_index; i -= 1 {
		if mac_events[i].window == window {
			ordered_remove(&mac_events, i)
		}
	}
	window.platform = {}
}

@(private="package")
platform_show_window :: proc(window: ^Window, show: bool) -> bool {
	NS.scoped_autoreleasepool()
	handle := window.platform.handle
	if show {
		if window.ui.drag.element != NO_ELEMENT {
			mac_send(nil, mac_receiver(handle), "orderFront:", objc.id(nil))
		} else {
			mac_send(nil, mac_receiver(handle), "makeKeyAndOrderFront:", objc.id(nil))
			mac_application->activateIgnoringOtherApps(true)
		}
	} else {
		mac_send(nil, mac_receiver(handle), "orderOut:", objc.id(nil))
	}
	return mac_send(bool, mac_receiver(handle), "isVisible") == show
}

@(private="package")
platform_window_visible :: proc(window: ^Window) -> bool {
	handle := window.platform.handle
	return mac_send(bool, mac_receiver(handle), "isVisible") && !mac_send(bool, mac_receiver(handle), "isMiniaturized")
}

@(private="package")
platform_window_action :: proc(window: ^Window, action: Window_Action) -> bool {
	handle := mac_receiver(window.platform.handle)
	#partial switch action {
	case .Minimize:
		if platform_window_state(window) == .Fullscreen {
			return false
		}
		mac_send(nil, handle, "miniaturize:", objc.id(nil))
	case .Toggle_Maximize:
		if window.ui.live_frame_storage != nil {
			// Run AppKit's blocking animation from the native pump, where a
			// resize callback can safely advance the frame.
			window.platform.zoom_pending = !window.platform.zoom_pending
		} else {
			mac_send(nil, handle, "zoom:", objc.id(nil))
		}
	case .Toggle_Fullscreen: mac_send(nil, handle, "toggleFullScreen:", objc.id(nil))
	case: return false
	}
	return true
}

@(private="package")
platform_window_state :: proc(window: ^Window) -> Window_State {
	handle := mac_receiver(window.platform.handle)
	if mac_send(bool, handle, "isMiniaturized") { return .Minimized }
	if .FullScreen in mac_send(AppKit.WindowStyleMask, handle, "styleMask") { return .Fullscreen }
	if mac_send(bool, handle, "isZoomed") { return .Maximized }
	return .Normal
}

@(private="package")
platform_window_is_active :: proc(window: ^Window) -> bool {
	return mac_send(bool, mac_receiver(window.platform.handle), "isKeyWindow")
}

@(private="file")
mac_desktop_top :: proc() -> f64 {
	screens := mac_send(objc.id, mac_receiver(objc_getClass("NSScreen")), "screens")
	first := mac_send(objc.id, mac_receiver(screens), "firstObject")
	frame := mac_send(NS.Rect, mac_receiver(first), "frame")
	return frame.origin.y + frame.size.height
}

@(private="file")
mac_content_rect :: proc "contextless" (window: ^Window) -> NS.Rect {
	view := window.platform.view
	bounds := mac_send(NS.Rect, mac_receiver(view), "bounds")
	in_window := mac_send(NS.Rect, mac_receiver(view), "convertRect:toView:", bounds, objc.id(nil))
	return mac_send(NS.Rect, mac_receiver(window.platform.handle), "convertRectToScreen:", in_window)
}

@(private="package")
platform_window_position :: proc(window: ^Window) -> [2]f32 {
	NS.scoped_autoreleasepool()
	content := mac_content_rect(window)
	return {f32(content.origin.x), f32(mac_desktop_top() - content.origin.y - content.size.height)}
}

@(private="package")
platform_set_window_position :: proc(window: ^Window, position: [2]i32) -> bool {
	NS.scoped_autoreleasepool()
	handle := window.platform.handle
	frame := mac_send(NS.Rect, mac_receiver(handle), "frame")
	content := mac_content_rect(window)
	point := NS.Point{
		f64(position[0]) + frame.origin.x - content.origin.x,
		mac_desktop_top() - f64(position[1]) +
			frame.origin.y + frame.size.height - content.origin.y - content.size.height,
	}
	mac_send(nil, mac_receiver(handle), "setFrameTopLeftPoint:", point)
	return true
}

@(private="package")
platform_window_size :: proc(window: ^Window) -> [2]i32 {
	bounds := mac_send(NS.Rect, mac_receiver(window.platform.view), "bounds")
	return {i32(bounds.size.width + 0.5), i32(bounds.size.height + 0.5)}
}

@(private="package")
platform_set_window_size :: proc(window: ^Window, size: [2]i32) -> bool {
	NS.scoped_autoreleasepool()
	value := NS.Size{f64(max(1, size[0])), f64(max(1, size[1]))}
	mac_send(nil, mac_receiver(window.platform.handle), "setContentSize:", value)
	mac_resize_layer(window)
	return true
}

@(private="package")
platform_window_scales :: proc(window: ^Window) -> (f32, f32) {
	return f32(mac_send(f64, mac_receiver(window.platform.handle), "backingScaleFactor")), 1
}

@(private="package")
platform_window_refresh_rate :: proc(window: ^Window) -> u64 {
	NS.scoped_autoreleasepool()
	screen := mac_send(^AppKit.Screen, mac_receiver(window.platform.handle), "screen")
	selector := sel_registerName("maximumFramesPerSecond")
	if mac_send(bool, mac_receiver(screen), "respondsToSelector:", selector) {
		rate := mac_send(NS.Integer, mac_receiver(screen), "maximumFramesPerSecond")
		if rate > 0 {
			return u64(rate)
		}
	}
	return 60
}

@(private="file")
mac_resize_layer :: proc(window: ^Window) {
	if window.platform.layer == nil {
		return
	}
	bounds := mac_send(NS.Rect, mac_receiver(window.platform.view), "bounds")
	scale := mac_send(f64, mac_receiver(window.platform.handle), "backingScaleFactor")
	pixels := NS.Size{bounds.size.width * scale, bounds.size.height * scale}
	mac_send(nil, mac_receiver(window.platform.layer), "setContentsScale:", scale)
	mac_send(nil, mac_receiver(window.platform.layer), "setDrawableSize:", pixels)
}

@(private="package")
platform_poll_event :: proc(app: ^UI, poll_native: bool, deadline: u64) -> (Platform_Event, bool) {
	NS.scoped_autoreleasepool()
	poll: for {
		if mac_event_index < len(mac_events) {
			event := mac_events[mac_event_index]
			mac_event_index += 1
			return event, true
		}
		clear(&mac_events)
		mac_event_index = 0
		if !poll_native || !app.running {
			return {}, false
		}
		for window in app.windows {
			if window.platform.zoom_pending && !window.close_requested {
				window.platform.zoom_pending = false
				// A frame callback can close the window during the animation.
				handle := mac_send(objc.id, mac_receiver(window.platform.handle), "retain")
				mac_send(nil, mac_receiver(handle), "zoom:", objc.id(nil))
				mac_send(nil, mac_receiver(handle), "release")
				continue poll
			}
		}
		until := NS.Date.distantPast()
		now := monotonic_ns()
		if deadline > now {
			// Keep AppKit servicing input and window updates between frames.
			until = NS.Date.dateWithTimeIntervalSinceNow(NS.TimeInterval(f64(deadline - now) / 1_000_000_000))
		}
		event := mac_application->nextEventMatchingMask(transmute(AppKit.EventMask)~u64(0), until, NS.DefaultRunLoopMode, bool(true))
		if event == nil {
			mac_application->updateWindows()
			if len(mac_events) != 0 {
				continue
			}
			return {}, false
		}
		handle := mac_send(^AppKit.Window, mac_receiver(event), "window")
		handled := false
		for window in app.windows {
			if handle == window.platform.handle {
				handled = mac_queue_input(window, event)
				break
			}
		}
		if !handled {
			mac_application->sendEvent(event)
		}
	}
}

@(private="file")
mac_queue_input :: proc(window: ^Window, native_event: ^AppKit.Event) -> bool {
	kind := mac_send(AppKit.EventType, mac_receiver(native_event), "type")
	event := Platform_Event{window = window, timestamp = monotonic_ns()}
	#partial switch kind {
	case .KeyDown, .KeyUp:
		key := mac_key(native_event)
		if key == .Unknown {
			return false
		}
		event.kind = .Key
		event.key = {
			key = key, modifiers = mac_modifiers(mac_send(AppKit.EventModifierFlags, mac_receiver(native_event), "modifierFlags")),
			down = kind == .KeyDown, repeat = kind == .KeyDown && mac_send(bool, mac_receiver(native_event), "isARepeat"),
			timestamp = event.timestamp,
		}
	case .LeftMouseDown, .LeftMouseUp, .MouseMoved, .LeftMouseDragged, .ScrollWheel:
		location := mac_send(NS.Point, mac_receiver(native_event), "locationInWindow")
		point := mac_send(NS.Point, mac_receiver(window.platform.view), "convertPoint:fromView:", location, objc.id(nil))
		bounds := mac_send(NS.Rect, mac_receiver(window.platform.view), "bounds")
		event.position = {f32(point.x), f32(bounds.size.height - point.y)}
		inside := point.x >= 0 && point.y >= 0 && point.x < bounds.size.width && point.y <= bounds.size.height
		#partial switch kind {
		case .LeftMouseDown:
			mac_clear_title_bar_press(window)
			if !inside { return false }
			if window_hit_at(window, event.position) == .Drag {
				mac_title_bar_press(window, native_event)
				return true
			}
			event.kind = .Mouse_Down
			event.modifiers = mac_modifiers(mac_send(AppKit.EventModifierFlags, mac_receiver(native_event), "modifierFlags"))
			event.clicks = u8(clamp(mac_send(NS.Integer, mac_receiver(native_event), "clickCount"), 1, 255))
		case .LeftMouseUp:
			if window.platform.title_bar_down != nil {
				mac_clear_title_bar_press(window)
				return true
			}
			event.kind = .Mouse_Up
		case .LeftMouseDragged:
			if down := window.platform.title_bar_down; down != nil {
				window.platform.title_bar_down = nil
				defer mac_send(nil, mac_receiver(down), "release")
				mac_send(nil, mac_receiver(window.platform.handle), "performWindowDragWithEvent:", down)
				return true
			}
			event.kind = .Mouse_Move
		case .MouseMoved:
			event.kind = .Mouse_Move
		case .ScrollWheel:
			if !inside { return false }
			event.kind = .Wheel
			event.wheel = f32(mac_send(f64, mac_receiver(native_event), "scrollingDeltaY"))
			if mac_send(bool, mac_receiver(native_event), "hasPreciseScrollingDeltas") {
				event.wheel_direct = true
				event.wheel_distance = event.wheel / window_scale(window)
				event.wheel /= 10 // Convert trackpad points to wheel steps.
			}
		}
	case:
		return false
	}
	append(&mac_events, event)
	return false
}

@(private="file")
mac_title_bar_press :: proc(window: ^Window, event: ^AppKit.Event) {
	if platform_window_state(window) == .Fullscreen {
		return
	}
	handle := mac_receiver(window.platform.handle)
	if !platform_window_is_active(window) {
		mac_send(nil, handle, "makeKeyAndOrderFront:", objc.id(nil))
	}
	if mac_send(NS.Integer, mac_receiver(event), "clickCount") != 2 {
		// Wait for movement before handing AppKit the original mouse-down event.
		window.platform.title_bar_down = mac_send(^AppKit.Event, mac_receiver(event), "retain")
		return
	}
	defaults := mac_send(objc.id, mac_receiver(objc_getClass("NSUserDefaults")), "standardUserDefaults")
	key := mac_string("AppleActionOnDoubleClick")
	defer mac_send(nil, mac_receiver(key), "release")
	preference := mac_send(^NS.String, mac_receiver(defaults), "stringForKey:", key)
	action := preference == nil ? "" : string(preference->UTF8String())
	switch action {
	case "None":
	case "Minimize": _ = window_action(window, .Minimize)
	case "", "Maximize", "Zoom", "Fill": _ = window_action(window, .Toggle_Maximize)
	}
}

@(private="file")
mac_clear_title_bar_press :: proc(window: ^Window) {
	if down := window.platform.title_bar_down; down != nil {
		window.platform.title_bar_down = nil
		mac_send(nil, mac_receiver(down), "release")
	}
}

@(private="package")
platform_mouse_window :: proc(app: ^UI) -> ^Window {
	NS.scoped_autoreleasepool()
	mouse := mac_send(NS.Point, mac_receiver(objc_getClass("NSEvent")), "mouseLocation")
	number := mac_send(NS.Integer, mac_receiver(objc_getClass("NSWindow")), "windowNumberAtPoint:belowWindowWithWindowNumber:",
		mouse, NS.Integer(0))
	for window in app.windows {
		if number == mac_send(NS.Integer, mac_receiver(window.platform.handle), "windowNumber") {
			return window
		}
	}
	return nil
}

@(private="package")
platform_mouse_state :: proc() -> ([2]f32, bool) {
	NS.scoped_autoreleasepool()
	class := objc_getClass("NSEvent")
	mouse := mac_send(NS.Point, mac_receiver(class), "mouseLocation")
	buttons := mac_send(NS.UInteger, mac_receiver(class), "pressedMouseButtons")
	return {f32(mouse.x), f32(mac_desktop_top() - mouse.y)}, buttons & 1 != 0
}

@(private="package")
platform_capture_mouse :: proc(window: ^Window) {
	// AppKit routes drag and release to the window that received the mouse down.
}

@(private="package")
platform_set_cursor :: proc(app: ^UI, cursor: Cursor) {
	window := platform_mouse_window(app)
	if window == nil && app.captured == NO_ELEMENT && app.drag.element == NO_ELEMENT {
		return
	}
	if window != nil && app.captured == NO_ELEMENT && app.drag.element == NO_ELEMENT {
		mouse, _ := platform_mouse_state()
		offset := mouse - platform_window_position(window)
		size := platform_window_size(window)
		if offset.x < 0 || offset.y < 0 || offset.x >= f32(size[0]) || offset.y >= f32(size[1]) {
			return
		}
	}
	class := objc_getClass("NSCursor")
	shape: objc.id
	switch cursor {
	case .Default: shape = mac_send(objc.id, mac_receiver(class), "arrowCursor")
	case .Pointer: shape = mac_send(objc.id, mac_receiver(class), "pointingHandCursor")
	case .Move: shape = mac_send(objc.id, mac_receiver(class), "closedHandCursor")
	case .Text: shape = mac_send(objc.id, mac_receiver(class), "IBeamCursor")
	case .Resize_Horizontal: shape = mac_send(objc.id, mac_receiver(class), "resizeLeftRightCursor")
	}
	mac_send(nil, mac_receiver(shape), "set")
}

@(private="file")
mac_modifiers :: proc(flags: AppKit.EventModifierFlags) -> Key_Modifiers {
	result: Key_Modifiers
	if .Shift in flags { result += {.Shift} }
	if .Control in flags { result += {.Ctrl} }
	if .Option in flags { result += {.Alt} }
	if .Command in flags { result += {.Gui} }
	return result
}

@(private="file")
mac_key :: proc(event: ^AppKit.Event) -> Key {
	code := mac_send(u16, mac_receiver(event), "keyCode")
	switch code {
	case 36: return .Enter
	case 48: return .Tab
	case 49: return .Space
	case 51: return .Backspace
	case 53: return .Escape
	case 76: return .Keypad_Enter
	case 96: return .F5
	case 97: return .F6
	case 98: return .F7
	case 99: return .F3
	case 100: return .F8
	case 101: return .F9
	case 103: return .F11
	case 109: return .F10
	case 111: return .F12
	case 114: return .Insert
	case 115: return .Home
	case 116: return .Page_Up
	case 117: return .Delete
	case 119: return .End
	case 121: return .Page_Down
	case 118: return .F4
	case 120: return .F2
	case 122: return .F1
	case 123: return .Left
	case 124: return .Right
	case 125: return .Down
	case 126: return .Up
	}
	text := mac_send(^NS.String, mac_receiver(event), "charactersIgnoringModifiers")
	if text != nil && text->length() == 1 {
		character := mac_send(u16, mac_receiver(text), "characterAtIndex:", NS.UInteger(0))
		if 'a' <= character && character <= 'z' { return Key(int(Key.A) + int(character - 'a')) }
		if 'A' <= character && character <= 'Z' { return Key(int(Key.A) + int(character - 'A')) }
		if '0' <= character && character <= '9' { return Key(int(Key.Digit_0) + int(character - '0')) }
	}
	return .Unknown
}

@(private="package")
platform_text_input :: proc(window: ^Window, enabled: bool) {
	if window.platform.text_input == enabled {
		return
	}
	window.platform.text_input = enabled
	if !enabled {
		platform_clear_composition(window)
	}
}

@(private="package")
platform_clear_composition :: proc(window: ^Window) {
	NS.scoped_autoreleasepool()
	input := mac_send(objc.id, mac_receiver(window.platform.view), "inputContext")
	mac_send(nil, mac_receiver(input), "discardMarkedText")
	mac_clear_marked(window)
}

@(private="package")
platform_text_input_area :: proc(window: ^Window, area: [4]i32) {
	if window.platform.ime_area == area {
		return
	}
	window.platform.ime_area = area
	NS.scoped_autoreleasepool()
	input := mac_send(objc.id, mac_receiver(window.platform.view), "inputContext")
	mac_send(nil, mac_receiver(input), "invalidateCharacterCoordinates")
}

@(private="package")
platform_clipboard_set :: proc(window: ^Window, value: string) -> bool {
	NS.scoped_autoreleasepool()
	board := AppKit.Pasteboard.generalPasteboard()
	str := mac_string(value)
	defer mac_send(nil, mac_receiver(str), "release")
	board->clearContents()
	return board->setString(str, AppKit.PasteboardTypeString)
}

@(private="package")
platform_clipboard_get :: proc(window: ^Window) -> string {
	NS.scoped_autoreleasepool()
	board := AppKit.Pasteboard.generalPasteboard()
	str := board->stringForType(AppKit.PasteboardTypeString)
	return mac_copy_text(str)
}

@(private="package")
platform_create_surface :: proc(window: ^Window, instance: vk.Instance) -> (vk.SurfaceKHR, vk.Result) {
	info := vk.MetalSurfaceCreateInfoEXT{
		sType = .METAL_SURFACE_CREATE_INFO_EXT,
		pLayer = cast(^vk.CAMetalLayer)window.platform.layer,
	}
	surface: vk.SurfaceKHR
	result := vk.CreateMetalSurfaceEXT(instance, &info, nil, &surface)
	return surface, result
}

@(private="package")
platform_clips_drawable :: true

@(private="package")
platform_set_window_clip :: proc(window: ^Window, circle: Maybe(Window_Circle)) -> bool {
	clipped := circle != nil
	if window.platform.clip_active == clipped {
		return true
	}
	window.platform.clip_active = clipped
	NS.scoped_autoreleasepool()
	handle := mac_receiver(window.platform.handle)
	style := mac_send(AppKit.WindowStyleMask, handle, "styleMask")
	if .Titled in style && !window.custom_title_bar {
		// Full-size content puts the title-bar area inside the clipped drawable.
		// Preserve the client rectangle and reuse the existing Metal layer.
		client := mac_content_rect(window)
		if clipped {
			style += {.FullSizeContentView}
		} else {
			style -= {.FullSizeContentView}
		}
		mac_send(nil, handle, "setStyleMask:", style)
		frame := clipped ? client : mac_send(NS.Rect, handle, "frameRectForContentRect:", client)
		mac_send(nil, handle, "setFrame:display:", frame, bool(true))
		mac_set_title_bar_hidden(window.platform.handle, clipped)
		mac_resize_layer(window)
	}
	mac_send(nil, handle, "setHasShadow:", bool(!clipped))
	return true
}

@(private="file")
mac_set_title_bar_hidden :: proc(window: ^AppKit.Window, hidden: bool) {
	handle := mac_receiver(window)
	mac_send(nil, handle, "setTitleVisibility:", hidden ? AppKit.WindowTitleVisibility.Hidden : .Visible)
	mac_send(nil, handle, "setTitlebarAppearsTransparent:", hidden)
	buttons := [?]AppKit.WindowButton{.CloseButton, .MiniaturizeButton, .ZoomButton}
	for button in buttons {
		control := mac_send(objc.id, handle, "standardWindowButton:", button)
		mac_send(nil, mac_receiver(control), "setHidden:", hidden)
	}
}

@(private="file")
mac_string :: proc(value: string) -> ^NS.String {
	object := mac_send(^NS.String, mac_receiver(objc_getClass("NSString")), "alloc")
	return mac_send(^NS.String, mac_receiver(object), "initWithBytes:length:encoding:",
		raw_data(value), NS.UInteger(len(value)), NS.StringEncoding(NS.UTF8StringEncoding))
}

@(private="file")
mac_copy_text :: proc(value: ^NS.String) -> string {
	if value == nil {
		return ""
	}
	return strings.clone(string(value->UTF8String()), context.temp_allocator)
}

@(private="file")
mac_window_from_view :: proc "contextless" (view: objc.id) -> ^Window {
	pointer: rawptr
	object_getInstanceVariable(view, "_fluidWindow", &pointer)
	return cast(^Window)pointer
}

@(private="file")
mac_view_accepts_first_responder :: proc "c" (view: objc.id, cmd: objc.SEL) -> bool {
	return true
}

@(private="file")
mac_view_key_down :: proc "c" (view: objc.id, cmd: objc.SEL, event: objc.id) {
	window := mac_window_from_view(view)
	if window != nil && window.platform.text_input {
		flags := mac_send(AppKit.EventModifierFlags, mac_receiver(event), "modifierFlags")
		if .Command not_in flags && .Control not_in flags {
			events := mac_send(objc.id, mac_receiver(objc_getClass("NSArray")), "arrayWithObject:", event)
			mac_send(nil, mac_receiver(view), "interpretKeyEvents:", events)
		}
	}
}

@(private="file")
mac_should_terminate :: proc "c" (self: objc.id, cmd: objc.SEL, application: objc.id) -> NS.UInteger {
	context = runtime.default_context()
	append(&mac_events, Platform_Event{kind = .Quit, timestamp = monotonic_ns()})
	return 0 // NSTerminateCancel. Fluid exits its own event loop and releases resources.
}

@(private="file")
mac_window_should_close :: proc "c" (view: objc.id, cmd: objc.SEL, handle: objc.id) -> bool {
	context = runtime.default_context()
	if window := mac_window_from_view(view); window != nil {
		append(&mac_events, Platform_Event{kind = .Close, window = window, timestamp = monotonic_ns()})
	}
	return false
}

@(private="file")
mac_window_resized :: proc "c" (view: objc.id, cmd: objc.SEL, note: objc.id) {
	context = runtime.default_context()
	if window := mac_window_from_view(view); window != nil {
		mac_resize_layer(window)
		append(&mac_events, Platform_Event{kind = .Resize, window = window, timestamp = monotonic_ns()})
		// AppKit can deliver intermediate sizes while the resize timer is
		// blocked by a native window animation.
		live_resize_frame(window)
	}
}

@(private="file")
mac_window_exited_fullscreen :: proc "c" (view: objc.id, cmd: objc.SEL, note: objc.id) {
	context = runtime.default_context()
	if window := mac_window_from_view(view); window != nil && window.custom_title_bar {
		mac_set_title_bar_hidden(window.platform.handle, true)
	}
}

@(private="file")
mac_window_live_resize_started :: proc "c" (view: objc.id, cmd: objc.SEL, note: objc.id) {
	context = runtime.default_context()
	window := mac_window_from_view(view)
	if window == nil || window.platform.live_resize_timer != nil {
		return
	}
	interval := 1 / f64(platform_window_refresh_rate(window))
	timer := mac_send(objc.id, mac_receiver(objc_getClass("NSTimer")),
		"timerWithTimeInterval:target:selector:userInfo:repeats:", interval, view,
		sel_registerName("fluidLiveResizeTick:"), objc.id(nil), bool(true))
	window.platform.live_resize_timer = timer
	loop := mac_send(objc.id, mac_receiver(objc_getClass("NSRunLoop")), "mainRunLoop")
	mac_send(nil, mac_receiver(loop), "addTimer:forMode:", timer, NS.RunLoopCommonModes)
}

@(private="file")
mac_window_live_resize_ended :: proc "c" (view: objc.id, cmd: objc.SEL, note: objc.id) {
	context = runtime.default_context()
	if window := mac_window_from_view(view); window != nil {
		mac_stop_live_resize(window)
	}
}

@(private="file")
mac_stop_live_resize :: proc(window: ^Window) {
	if timer := window.platform.live_resize_timer; timer != nil {
		window.platform.live_resize_timer = nil
		mac_send(nil, mac_receiver(timer), "invalidate")
	}
}

@(private="file")
mac_live_resize_tick :: proc "c" (view: objc.id, cmd: objc.SEL, timer: objc.id) {
	context = runtime.default_context()
	if window := mac_window_from_view(view); window != nil && timer == window.platform.live_resize_timer {
		NS.scoped_autoreleasepool()
		live_resize_frame(window)
	}
}

@(private="file")
mac_window_resigned_key :: proc "c" (view: objc.id, cmd: objc.SEL, note: objc.id) {
	context = runtime.default_context()
	if window := mac_window_from_view(view); window != nil {
		mac_clear_title_bar_press(window)
		append(&mac_events, Platform_Event{kind = .Focus_Lost, window = window, timestamp = monotonic_ns()})
	}
}

@(private="file")
mac_mouse_exited :: proc "c" (view: objc.id, cmd: objc.SEL, event: objc.id) {
	context = runtime.default_context()
	if window := mac_window_from_view(view); window != nil {
		append(&mac_events, Platform_Event{kind = .Mouse_Leave, window = window, timestamp = monotonic_ns()})
	}
}

@(private="file")
mac_plain_string :: proc "contextless" (value: objc.id) -> ^NS.String {
	if mac_send(bool, mac_receiver(value), "isKindOfClass:", objc_getClass("NSAttributedString")) {
		return mac_send(^NS.String, mac_receiver(value), "string")
	}
	return cast(^NS.String)value
}

@(private="file")
mac_clear_marked :: proc "contextless" (window: ^Window) {
	mac_send(nil, mac_receiver(window.platform.marked), "release")
	window.platform.marked = nil
	window.platform.selection = {}
}

@(private="file")
mac_insert_text :: proc "c" (view: objc.id, cmd: objc.SEL, value: objc.id, replacement: NS.Range) {
	context = runtime.default_context()
	window := mac_window_from_view(view)
	if window == nil || !window.platform.text_input {
		return
	}
	text := mac_copy_text(mac_plain_string(value))
	mac_clear_marked(window)
	append(&mac_events, Platform_Event{kind = .Text_Input, window = window, timestamp = monotonic_ns(), text = {text}})
}

@(private="file")
mac_set_marked_text :: proc "c" (view: objc.id, cmd: objc.SEL, value: objc.id, selection, replacement: NS.Range) {
	context = runtime.default_context()
	window := mac_window_from_view(view)
	if window == nil || !window.platform.text_input {
		return
	}
	marked := mac_send(^NS.String, mac_receiver(mac_plain_string(value)), "copy")
	mac_clear_marked(window)
	window.platform.marked = marked
	window.platform.selection = selection
	start := mac_codepoint_count(marked, selection.location)
	end := mac_codepoint_count(marked, selection.location + selection.length)
	append(&mac_events, Platform_Event{kind = .Text_Edit, window = window, timestamp = monotonic_ns(), edit = {
		text = mac_copy_text(marked), start = start, length = max(0, end - start),
	}})
}

@(private="file")
mac_codepoint_count :: proc "contextless" (value: ^NS.String, length: NS.UInteger) -> i32 {
	limit := min(mac_send(NS.UInteger, mac_receiver(value), "length"), length)
	count: i32
	for i: NS.UInteger = 0; i < limit; i += 1 {
		unit := mac_send(u16, mac_receiver(value), "characterAtIndex:", i)
		if unit < 0xdc00 || unit > 0xdfff {
			count += 1
		}
	}
	return count
}

@(private="file")
mac_unmark_text :: proc "c" (view: objc.id, cmd: objc.SEL) {
	context = runtime.default_context()
	if window := mac_window_from_view(view); window != nil && window.platform.marked != nil {
		mac_clear_marked(window)
		if window.platform.text_input {
			append(&mac_events, Platform_Event{kind = .Text_Edit, window = window, timestamp = monotonic_ns()})
		}
	}
}

@(private="file")
mac_has_marked_text :: proc "c" (view: objc.id, cmd: objc.SEL) -> bool {
	window := mac_window_from_view(view)
	return window != nil && mac_send(NS.UInteger, mac_receiver(window.platform.marked), "length") != 0
}

@(private="file")
mac_marked_range :: proc "c" (view: objc.id, cmd: objc.SEL) -> NS.Range {
	window := mac_window_from_view(view)
	if window != nil {
		if length := mac_send(NS.UInteger, mac_receiver(window.platform.marked), "length"); length != 0 {
			return {0, length}
		}
	}
	return {NS.UInteger(NS.NotFound), 0}
}

@(private="file")
mac_selected_range :: proc "c" (view: objc.id, cmd: objc.SEL) -> NS.Range {
	if window := mac_window_from_view(view); window != nil {
		return window.platform.selection
	}
	return {}
}

@(private="file")
mac_valid_attributes :: proc "c" (view: objc.id, cmd: objc.SEL) -> objc.id {
	return mac_send(objc.id, mac_receiver(objc_getClass("NSArray")), "array")
}

@(private="file")
mac_attributed_substring :: proc "c" (view: objc.id, cmd: objc.SEL, bounds: NS.Range, actual: ^NS.Range) -> objc.id {
	window := mac_window_from_view(view)
	if window == nil || window.platform.marked == nil {
		return nil
	}
	str := window.platform.marked
	length := mac_send(NS.UInteger, mac_receiver(str), "length")
	if bounds.location >= length {
		return nil
	}
	range := NS.Range{bounds.location, min(bounds.length, length - bounds.location)}
	if actual != nil { actual^ = range }
	substring := mac_send(objc.id, mac_receiver(str), "substringWithRange:", range)
	result := mac_send(objc.id, mac_receiver(objc_getClass("NSAttributedString")), "alloc")
	result = mac_send(objc.id, mac_receiver(result), "initWithString:", substring)
	return mac_send(objc.id, mac_receiver(result), "autorelease")
}

@(private="file")
mac_character_rect :: proc "c" (view: objc.id, cmd: objc.SEL, bounds: NS.Range, actual: ^NS.Range) -> NS.Rect {
	window := mac_window_from_view(view)
	if window == nil {
		return {}
	}
	rect := mac_content_rect(window)
	area := window.platform.ime_area
	if actual != nil { actual^ = bounds }
	return {
		origin = {rect.origin.x + f64(area[0]), rect.origin.y + rect.size.height - f64(area[1] + area[3])},
		size = {f64(area[2]), f64(area[3])},
	}
}

@(private="file")
mac_character_index :: proc "c" (view: objc.id, cmd: objc.SEL, point: NS.Point) -> NS.UInteger {
	return NS.UInteger(NS.NotFound)
}

@(private="file")
mac_ignore_text_command :: proc "c" (view: objc.id, cmd: objc.SEL, action: objc.SEL) {}
