package fluid

import "core:math"
import "core:os"

Scroll_Viewport :: struct {
	element: Element_View,
	clip: IRect, // Physical pixels. Drawing inside the callback is already clipped.
	first, end: f64, // Visible content interval, including partial units.
	pixels_per_unit: f64,
}

Scroll_View_Definition :: struct {
	pins: Pins,
	color: Color,
	style: Style,
	stick_to_end: bool,
	state: rawptr,
	draw: proc(state: rawptr, viewport: Scroll_Viewport),
	release_graphics: proc(state: rawptr),
}

@(private="file")
Scroll_State :: struct {
	data: rawptr,
	draw: proc(state: rawptr, viewport: Scroll_Viewport),
	release_graphics: proc(state: rawptr),
	first, end, unit_height: f64,
	offset, target: f64,
	stick_to_end, following: bool,
	thumb_grab: Maybe(f32),
	drawn_at: u64,
}

create_scroll_view :: proc(window: ^Window, definition: Scroll_View_Definition) -> Element_ID {
	assert(definition.draw != nil)
	state := new(Scroll_State, os.heap_allocator())
	state^ = {
		data = definition.state, draw = definition.draw, release_graphics = definition.release_graphics,
		unit_height = 1, stick_to_end = definition.stick_to_end, following = definition.stick_to_end,
	}
	return create_element(window, {
		pins = definition.pins, color = definition.color, style = definition.style,
		surface = true, focusable = true, draw = draw_scroll_view,
		behavior = {
			state = state, input = scroll_view_input, release_graphics = release_scroll_view_graphics,
			destroy = destroy_scroll_view,
		},
	})
}

// The content bounds are absolute. One content unit occupies unit_height UI units.
// Arrows move by one content unit and a wheel notch moves by three.
set_scroll_content :: proc(ui: ^UI, id: Element_ID, first, end: f64, unit_height: f64 = 1) {
	assert(first <= end && unit_height > 0 && !math.is_inf(first) && !math.is_inf(end) && !math.is_inf(unit_height))
	state := get_scroll_state(ui, id)
	if state.first == state.end {
		state.offset, state.target = first, first
	}
	state.first, state.end, state.unit_height = first, end, unit_height
}

scroll_to_end :: proc(ui: ^UI, id: Element_ID) {
	state := get_scroll_state(ui, id)
	layout := scroll_layout(state, element_view(ui, id))
	set_scroll_target(state, layout, layout.last, false)
}

scroll_follows_end :: proc(ui: ^UI, id: Element_ID) -> bool {
	return get_scroll_state(ui, id).following
}

@(private="file")
get_scroll_state :: proc(ui: ^UI, id: Element_ID) -> ^Scroll_State {
	behavior := element_behavior(ui, id)
	assert(behavior.input == scroll_view_input)
	return cast(^Scroll_State)behavior.state
}

@(private="file")
release_scroll_view_graphics :: proc(data: rawptr) {
	state := cast(^Scroll_State)data
	if state.release_graphics != nil {
		state.release_graphics(state.data)
	}
}

@(private="file")
destroy_scroll_view :: proc(data: rawptr) {
	free(data, os.heap_allocator())
}

@(private="file")
Scroll_Layout :: struct {
	clip: IRect,
	track: Pins,
	scale: f32,
	pixels_per_unit, visible, last: f64,
}

@(private="file")
scroll_layout :: proc(state: ^Scroll_State, view: Element_View) -> Scroll_Layout {
	r := view.pins
	scale := pixel_scale(view.window)
	track := Pins{r.right - 0.8, r.top + 0.5, r.right - 0.4, r.bottom - 0.5}
	left := i32(math.round((r.left + 0.8) * scale))
	right := i32(math.round((track.left - 0.5) * scale))
	top := i32(math.round(track.top * scale))
	bottom := i32(math.round(track.bottom * scale))
	clip := IRect{left, top, max(0, right - left), max(0, bottom - top)}
	pixels_per_unit := state.unit_height * f64(scale)
	visible := f64(clip.h) / pixels_per_unit
	return {clip, track, scale, pixels_per_unit, visible, max(state.first, state.end - visible)}
}

@(private="file")
scroll_offset :: proc(state: ^Scroll_State, layout: Scroll_Layout) -> f64 {
	return state.following ? layout.last : clamp(state.offset, state.first, layout.last)
}

@(private="file")
set_scroll_target :: proc(state: ^Scroll_State, layout: Scroll_Layout, target: f64, smooth: bool) {
	state.offset = scroll_offset(state, layout)
	state.target = clamp(target, state.first, layout.last)
	state.following = state.stick_to_end && state.target == layout.last
	if !smooth || state.following {
		state.offset = state.target
	}
}

@(private="file")
advance_scroll :: proc(state: ^Scroll_State, layout: Scroll_Layout) {
	now := monotonic_ns()
	previous := state.drawn_at
	state.drawn_at = now
	state.offset = scroll_offset(state, layout)
	state.target = clamp(state.target, state.first, layout.last)
	if state.following || state.offset == state.target || previous == 0 {
		return
	}
	// Approach the latest wheel target with a 100 ms time to reach 95% of the distance.
	dt := f64(now - previous) / 1_000_000_000
	state.offset += (state.target - state.offset) * (1 - math.exp(-30 * dt))
	if math.abs(state.target - state.offset) * layout.pixels_per_unit < 0.25 {
		state.offset = state.target
	}
}

@(private="file")
scroll_thumb :: proc(state: ^Scroll_State, layout: Scroll_Layout) -> Pins {
	track := layout.track
	track_height := height(track)
	content_height := state.end - state.first
	thumb_height := track_height
	progress: f32
	if layout.last > state.first {
		thumb_height = clamp(track_height * f32(layout.visible / content_height), min(f32(1.25), track_height), track_height)
		progress = f32((scroll_offset(state, layout) - state.first) / (layout.last - state.first))
	}
	top := track.top + (track_height - thumb_height) * progress
	return {track.left, top, track.right, top + thumb_height}
}

@(private="file")
scroll_view_input :: proc(data: rawptr, ui: ^UI, id: Element_ID, event: Element_Event) -> bool {
	state := cast(^Scroll_State)data
	view := element_view(ui, id)
	layout := scroll_layout(state, view)
	first := scroll_offset(state, layout)
	#partial switch value in event {
	case Wheel_Event:
		if value != 0 {
			target := state.following ? first : clamp(state.target, state.first, layout.last)
			set_scroll_target(state, layout, target - 3 * f64(value), true)
		}
		return true
	case Precise_Scroll_Event:
		delta := 3 * f64(value.steps)
		if distance, ok := value.distance.?; ok {
			delta = f64(distance) / state.unit_height
		}
		if delta != 0 {
			set_scroll_target(state, layout, first - delta, false)
		}
		return true
	case Keyboard_Event:
		if !value.down { return false }
		page := max(1, layout.visible - 1)
		#partial switch value.key {
		case .Up:        first -= 1
		case .Down:      first += 1
		case .Page_Up:   first -= page
		case .Page_Down: first += page
		case .Home:      first = state.first
		case .End:       first = layout.last
		case: return false
		}
		set_scroll_target(state, layout, first, false)
		return true
	case Pointer_Event:
		track := layout.track
		thumb := scroll_thumb(state, layout)
		travel := height(track) - height(thumb)
		switch value.kind {
		case .Down:
			hit := Pins{track.left - 0.25, track.top, view.pins.right, track.bottom}
			if travel <= 0 || !contains(hit, value.point) { return false }
			on_thumb := contains({hit.left, thumb.top, hit.right, thumb.bottom}, value.point)
			state.thumb_grab = on_thumb ? value.point.y - thumb.top : height(thumb) / 2
			capture_pointer(ui, id)
			if on_thumb {
				set_scroll_target(state, layout, first, false)
				return true
			}
		case .Move:
		case .Up, .Cancel:
			state.thumb_grab = nil
		}
		if grab, dragging := state.thumb_grab.?; dragging && travel > 0 {
			progress := clamp(f64((value.point.y - grab - track.top) / travel), 0, 1)
			set_scroll_target(state, layout, state.first + progress * (layout.last - state.first), false)
			return true
		}
	}
	return false
}

@(private="file")
draw_scroll_view :: proc(view: Element_View) {
	state := get_scroll_state(view.ui, view.id)
	layout := scroll_layout(state, view)
	advance_scroll(state, layout)
	renderer := view.window.renderer
	paint_styled_surface(renderer, pixel_rect(view.pins, layout.scale), view.style,
		view.color, view.hovered, view.focused, layout.scale)
	if layout.clip.w == 0 || layout.clip.h == 0 { return }
	if layout.last > state.first {
		render_fill_rect(renderer, pixel_rect(layout.track, layout.scale), {30, 42, 57, 255})
		render_fill_rect(renderer, pixel_rect(scroll_thumb(state, layout), layout.scale), {139, 157, 178, 255})
	}
	previous := render_clip(renderer, layout.clip)
	defer restore_render_clip(renderer, previous)
	first := scroll_offset(state, layout)
	state.draw(state.data, {view, layout.clip, first, min(state.end, first + layout.visible), layout.pixels_per_unit})
}
