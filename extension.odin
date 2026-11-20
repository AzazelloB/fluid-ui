package fluid

// A drawing callback receives a read-only snapshot. It may use the renderer
// and text helpers, and must leave element membership and layout alone.
Element_View :: struct {
	ui: ^UI,
	id: Element_ID,
	window: ^Window,
	pins: Pins,
	label: string,
	color: Color,
	style: Style,
	text_size: f32,
	text_align: Text_Align,
	text_weight: Text_Weight,
	text_wrap: bool,
	text_color: Color,
	surface, hovered, pressed, focused: bool,
}

Element_Draw :: proc(view: Element_View)

element_view :: proc(ui: ^UI, id: Element_ID) -> Element_View {
	return make_element_view(ui, id, get_element(ui, id))
}

@(private="package")
make_element_view :: proc(ui: ^UI, id: Element_ID, element: ^Element) -> Element_View {
	view := Element_View{
		ui = ui, id = id, window = element.window, pins = element.pins,
		text_size = 1, text_color = element.window.text_color,
		hovered = ui.hovered == id, pressed = ui.pressed == id, focused = ui.focused == id,
	}
	if appearance := element_appearance(ui, id); appearance != nil {
		view.label, view.color, view.style = appearance.label, appearance.color, appearance.style
		view.text_size, view.text_align, view.text_weight = appearance.text_size, appearance.text_align, appearance.text_weight
		view.text_wrap, view.surface = appearance.text_wrap, appearance.surface
		view.text_color = appearance.text_color.? or_else view.text_color
	}
	return view
}

// A nil callback stops drawing the element. Input and updates still run.
set_draw :: proc(ui: ^UI, id: Element_ID, draw: Element_Draw) {
	get_element(ui, id).draw = draw
}

Element_Event :: union {
	Pointer_Event, Keyboard_Event, Text_Input_Event, Text_Editing_Event,
	Focus_Event, Wheel_Event, Precise_Scroll_Event, Focused_Frame,
}
Pointer_Event :: struct {
	kind: enum {Down, Move, Up, Cancel},
	point: [2]f32, // In UI units in the receiving element's window.
	timestamp: u64,
	clicks: u8,
	modifiers: Key_Modifiers, // Set on presses.
	inside: bool, // The element is the topmost hit at this point.
}
Focus_Event :: struct {
	focused: bool,
	commit: bool, // Ordinary blur can commit. Hiding, removal, and transfer cancel.
}
Wheel_Event :: distinct f32 // Signed vertical wheel steps.
Precise_Scroll_Event :: struct {
	steps: f32,
	distance: Maybe(f32), // Signed vertical distance in UI units when supplied by the platform.
}
Focused_Frame :: distinct u64 // Monotonic clock in nanoseconds.

// State stays at a stable address for the element's lifetime. Return true to
// consume pointer-down and keyboard events with an engine default action.
// Cancellation and resource callbacks release local state.
Element_Behavior :: struct {
	state: rawptr,
	input: proc(state: rawptr, ui: ^UI, id: Element_ID, event: Element_Event) -> bool,
	release_graphics: proc(state: rawptr),
	destroy: proc(state: rawptr),
}

// release_graphics runs before cross-window transfer,
// font changes and destruction. destroy runs once, when the element is removed.
element_behavior :: proc(ui: ^UI, id: Element_ID) -> Element_Behavior {
	return get_element(ui, id).behavior
}

@(private="package")
send_element_event :: proc(ui: ^UI, id: Element_ID, event: Element_Event) -> bool {
	behavior := get_element(ui, id).behavior
	return behavior.input != nil && behavior.input(behavior.state, ui, id, event)
}

// Invoke the press callback for a visible element.
invoke_press :: proc(ui: ^UI, id: Element_ID) {
	if is_active(ui, id) {
		call_press(ui, id)
	}
}

@(private="package")
call_press :: proc(ui: ^UI, id: Element_ID) {
	callback := get_element(ui, id).press
	if callback.call != nil {
		callback.call(callback.data, ui, id)
	}
}
