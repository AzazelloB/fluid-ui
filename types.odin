package fluid

import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

Text_Size :: enum {Body, Caption, Heading, Title}
text_size_units :: proc(size: Text_Size) -> f32 {
	switch size {
	case .Body: return 1
	case .Caption: return 0.8
	case .Heading: return 1.5
	case .Title: return 2.5
	}
	unreachable()
}
Text_Align :: enum {Center, Left}

Style :: struct {
	radius: f32,
	border: Color,
	border_width: f32,
	shadow: f32,
}

Element_Kind :: enum {Panel, Button, Label}
Color :: sdl3.Color

// Plain numbers are multiples of the UI's base font size. Pins describe an
// axis-aligned rectangle; right/bottom are coordinates, not dimensions.
Pins :: struct {
	left, top, right, bottom: f32,
}

// Low 32 bits identify a slot; upper bits identify its lifetime.
Element_ID :: distinct int

Motion_Sample :: proc(from, to: Pins, progress: f32) -> Pins

// Transition clocks and callbacks are owned by Fluid, alongside their target.
Motion :: struct {
	from:      Pins,
	elapsed:   f64,
	progress:  f32,
	animation: Animation,
	complete:  Element_Callback,
	frame:     u64,
}

Element :: struct {
	generation:    u32,
	alive:         bool,
	space:         ^Window, // Viewport sources have no scene.
	kind:          Element_Kind,
	pins:          Pins,
	color:         sdl3.Color,
	label:         string,
	style:         Style,
	text_size:     Text_Size,
	text_align:    Text_Align,
	text_color:    Color,
	text:          ^ttf.Text,
	text_label:    string,
	selected:      bool,
	draggable:     bool,
	owner:         ^Scene,
	motion:        Motion,
	motion_serial: u64,
	press:         Element_Callback,
	update:        Update_Callback,
}
