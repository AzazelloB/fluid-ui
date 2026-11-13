package fluid

import "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

TEXT_PADDING :: 16
FONT_SIZE :: 16

Element_Kind :: enum {Panel, Button, Label}
Drag_Mode :: enum {References, Independent}
Rect :: sdl3.FRect
Color :: sdl3.Color

// Low 32 bits identify a slot; upper bits identify its lifetime.
Element_ID :: distinct int
Group_ID :: distinct int
Attribute :: enum {Left, Top, Right, Bottom, Width, Height, Content_Width}

Anchor :: struct {
	element:   Element_ID,
	attribute: Attribute,
	target:    bool, // Read the destination rather than an in-flight value.
}

// A group is an explicit set of references, not an ownership relationship.
Maximum :: struct {
	group:     Group_ID,
	attribute: Attribute,
	padding:   f32,
	minimum:   f32,
}

Distance :: struct {
	from, to: Anchor,
}

Motion_Sample :: proc(from, to: Rect, progress: f32) -> Rect

// Transition clocks and callbacks are owned by Fluid, alongside their target.
Motion :: struct {
	from:      Rect,
	elapsed:   f64,
	progress:  f32,
	animation: Animation,
	complete:  Element_Callback,
	frame:     u64,
}

Value :: struct {
	// An empty source makes offset a literal value.
	source: union {Anchor, Maximum, Distance},
	offset: f32,
}

Element :: struct {
	generation:    u32,
	alive:         bool,
	space:         ^Window, // Viewport sources have no scene.
	kind:          Element_Kind,
	position:      [2]Value,
	size:          [2]Value,
	color:         sdl3.Color,
	label:         string,
	text:          ^ttf.Text,
	text_label:    string,
	selected:      bool,
	draggable:     bool,
	drag_mode:     Drag_Mode,
	owner:         ^Scene,
	motion:        Motion,
	motion_serial: u64,
	press:         Element_Callback,
	update:        Update_Callback,
}
