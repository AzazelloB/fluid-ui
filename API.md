# Importing Fluid UI

The repository root is the engine package. It owns element IDs, geometry,
windows, input routing, and drawing primitives. The optional
`elements/` package builds reusable controls on that API. The standalone
showcase at `examples/showcase/` imports both packages and supplies its own
layout and presentation.

## Custom elements and styling

Use `fluid.create_element(window, definition)` to construct an element owned by
a window. Set `pressable` for default click and keyboard activation,
or supply an `Element_Behavior` to process routed input with your own state.
The engine owns focus, pointer capture, and the lifetime of the element.
It calls `release_graphics` before invalidating renderer or font resources
and `destroy` when the element is removed.

Use `set_hidden(ui, id)` to keep an element's ID, state, and draw order while
pausing drawing, input, updates, and animation. Pass `false` to show it again.
Hiding cancels focus and pointer interaction. `remove(ui, id)` destroys the
element and invalidates its ID. Use `remove_all(ui, ids)` to remove a list of
elements through the same cleanup path. Expired and repeated IDs are skipped.
A page can remove its elements on exit and recreate them from app-owned state.

Drawing is opt-in for engine elements. Supply a `draw` callback at creation or
use `fluid.set_draw` to replace it. Pass `nil` to stop drawing. Panels, labels,
and other stock controls in `elements` install their own draw callbacks. The
callback receives an `Element_View` with the current bounds,
text style, and interaction state. `render_clip` intersects the current drawing
clip and returns the previous rectangle for `restore_render_clip`. The Controls
showcase paints the Name
field in application code and calls `elements.draw_field_text` to draw editing
content with app-specified placeholder, selection, and caret colors. Custom choice drawing can read `elements.choice_slots` and
`elements.choice_slot`, including drag previews. Custom confirmation drawing
can read `elements.confirmation_progress` for the animated fill.

## Fragment shaders

Call `render_shader` from a drawing callback to fill a physical-pixel `FRect`
with an application fragment shader. Use `pixel_rect(view.pins,
pixel_scale(view.window))` to convert element bounds. Shader draws follow normal
draw order, `render_clip`, and any active window clip.

Include `shaders/fluid.frag.glsl` and implement `shade`. `uv` runs from the
upper-left `(0, 0)` to the lower-right `(1, 1)` of the original rectangle,
`size` gives its physical-pixel dimensions, and `data` carries four floats
supplied by the caller. Return straight RGBA. Fluid handles premultiplication.

```glsl
#version 450
#extension GL_GOOGLE_include_directive : require
#include "fluid.frag.glsl"

vec4 shade(vec2 uv, vec2 size, vec4 data) {
    return vec4(uv, data.x, 1.0);
}
```

Compile the Bamboo Forest shader from the repository root with
`glslang -V -Ishaders examples/showcase/shaders/bamboo.frag -o examples/showcase/shaders/bamboo.frag.spv`.
Embed the compiled module with `#load("path/to/file.frag.spv", []u32)` and
pass it to `render_shader(renderer, pixels, fragment, data)`. Use trusted
application shaders and keep the SPIR-V storage immutable for the UI session.
Each window caches its Vulkan pipeline for that storage. The call returns
`false` if drawing is unavailable or pipeline creation fails, so the callback
can draw a fallback.

# Units and geometry

All public lengths are plain `f32` values in UI units. One UI unit equals
16 logical points (`UI_UNIT_POINTS`). Pins, radii, text measurements, window
sizes and positions, and pointer coordinates use that unit. Display density is
handled by the platform window and Vulkan renderer.

## Pass values

`bounds` returns a struct of numeric edges. Widgets take the same struct:

```odin
viewport := fluid.bounds(ui, ui.window.viewport)
sidebar := elements.panel(ui.window, {
    left = viewport.right - 18.75,
    top = 1.5,
    right = viewport.right - 2.25,
    bottom = viewport.bottom - 1.5,
}, color)
```

There are no layout callbacks, stored expressions, or implicit references.
Changing `viewport` afterward does not change `sidebar`. To respond to resizing
or another element moving, calculate new values and send them again. Each demo
owns that work in its ordinary update handler. `fluid.run` keeps calling update
and drawing callbacks while a window is being resized on Windows and macOS.

`Pins` contains `left`, `top`, `right`, and `bottom`. Those are coordinates, not
width/height. Fixed size is ordinary math: `right = left + width`. Centering and
proportions also use ordinary math. Omitted fields default to zero. Crossed
edges collapse to zero extent; empty rectangles are not drawn or hit.
Non-finite pins assert.

`width(pins)` and `height(pins)` return nonnegative dimensions.
`rect(x, y, width, height)` builds edge coordinates from a position and size.
`contains(pins, point)` includes the left and top edges and excludes the right
and bottom edges.
`translated(pins, {dx, dy})` moves both corners without changing size.

`set_text_style` accepts regular or bold weight and left, center, or right
alignment. `set_text_wrap(ui, id)` lays text out from the top of its bounds,
wraps it to the available width, and clips it to the bounds. Use
`text_line_height(window, size, weight)` to size the visible area by line count
or pass a wrap width to `measure_text` to measure the full block.

## Update and animate

- `set_layout(ui, id, pins)` sets numeric pins and cancels any animation.
- `animate_to(ui, id, pins, animation)` animates from the current visible pins
  to the supplied destination.
- `set_target(ui, id, pins)` updates the destination without restarting the
  animation. Without an animation, the new pins take effect immediately.
- `bounds(ui, id)` reads the visible pins. Animation samplers receive and
  return `Pins`.

`on_update` registers one callback per frame for a visible element. Hiding or
removing an element cancels its remaining update for that frame. Callbacks run
in registration order, independent of stacking. Showing an element rejoins the
end of the update list. Updates added or shown during the pass start next frame.

Dragging moves the element's numeric pins. Other elements move with it only if
application code updates them. Removing an element invalidates its ID; other
elements retain their own values.

## Pointer input

Pointer hit testing checks active elements from front to back. An element
with the default `.Auto` pointer behavior receives hits when it is pressable,
focusable, draggable, or has an input or press handler. Use
`set_pointer_behavior(ui, id, .Pass)` to let hits through or `.Block` to
stop hits at the element. For example, a scrim can block the controls behind
it while a Back button above it still receives hits.

Presses use the coordinates of the mouse-down event. Behavior callbacks see
hover from before behavior dispatch. Fluid refreshes hover again after
layout and window changes so the cursor and drawing use the same result.
The stock elements use `Style.hover_border` to change the border while hovered.

## Scroll views

Use `elements.create_scroll_view` for a vertical viewport with clipping, a
scrollbar, wheel easing, direct trackpad scrolling, and keyboard navigation.
Its draw callback receives the visible interval in content coordinates and the
clip rectangle in physical pixels. Draw only the content in that interval. To
place a content coordinate `y`, use `clip.y + (y - first) * pixels_per_unit`.

`elements.set_scroll_content` sets the absolute beginning and end of the content
and the height of one content unit in UI units. One unit can represent a row or
any other fixed vertical step. Keeping absolute coordinates lets the view
hold its place when new content is appended or old content expires. Set
`stick_to_end` for a live feed. `elements.scroll_to_end` jumps to the end, and
`elements.scroll_follows_end` reports whether the view is following it.

Input handlers can consume `Precise_Scroll_Event` to receive direct scroll
motion. A handler that returns false receives the regular `Wheel_Event`
with normalized steps.

## Windows

Bounds and pointer coordinates are window-local.
`transfer(ui, id, destination_window)` preserves the element ID, animation
progress, and size in UI units.
It rebases the element and animation origins to preserve their desktop positions.

`pointer_position`, `set_window_size`, and window configuration use UI units
scaled for the window's display. `window_position` and `set_window_position`
use shared desktop coordinates, expressed in native desktop units divided by
`UI_UNIT_POINTS`. Use `desktop_point` and `window_point` to convert between
these spaces. Multiply UI units by `window_scale(window)` for native client
coordinates or by `pixel_scale(window)` for physical renderer pixels.

Use `.Custom_Title_Bar` in `Config.flags` to draw into the title area while
keeping native resizing. The application supplies the visuals and layout.
Mark an element with `set_window_hit(ui, id, .Drag)` for native title-bar
dragging. Interactive elements above it still receive normal input.
`elements.caption_button` provides platform-style close, minimize, and
maximize controls with caller-defined bounds. Custom buttons can use
`window_action`, `window_state`, and `window_is_active`. On Windows, mark a
custom maximize button with `.Maximize` for Snap Layouts.

`set_window_clip(window, Window_Mask{state, write})` installs a binary window
mask. The callback receives a zero-filled, row-major buffer with one byte per
physical pixel and the scale from window-local UI units to pixels. Write
nonzero bytes wherever the window should remain visible. Call
`set_window_clip(window)` to restore the full window.

On macOS, the window needs `.Transparent`, and the mask clips the drawable.
On Windows, the mask sets the native window region and also affects input.
To animate a mask, update its state in a `window_effect` callback and apply it
again. The showcase uses this to expand a circle from a zero-radius clip.

## Direct controls

These constructors and value setters are in the optional `elements` package.
Choose a control according to the value or action it represents.

| Constructor | Interaction |
| --- | --- |
| `button` | Click or press Enter or Space to invoke its `on_press` callback. Use `.Secondary` for a text-first action. |
| `dangerous_button` | Hold for 750 ms or tap three times in quick succession. Progress clears after 500 ms of inactivity. A cancelled press earns no tap. |
| `toggle` | Flip a Boolean. Apply an accepted change with `elements.set_toggle`. |
| `options` | Pick from visible choices or use the arrow keys. Apply an accepted index with `set_choice`. |
| `select` | Click a neighbor, use the arrow keys, or drag the current value to preview and release to commit. Selection stops at either end. |
| `number_input` | Drag or use the arrow keys to adjust. Double-click or press Enter or Space to edit. Enter or loss of focus commits a valid number, and Escape cancels. `Number_Options` configures the bounds, step, and display affixes. |
| `text_input`, `text_area` | Edit text directly. A text area also accepts newlines. Both support selection and standard clipboard shortcuts. |

`on_change` proposes a value synchronously. The handler decides whether to
apply it. The event carries a Boolean, choice index, number, or text string
alongside the element ID. Text in the event is borrowed for the callback.
`set_number` and `set_text_value` apply accepted values and keep their own
storage. Number drafts and select drag previews belong to the control.

Use `control_width` for content-based choice and number widths. Choice labels
are copied at creation and keep their order. The application still supplies
pins, visible field names, and any unit labels.

Tab and Shift+Tab move focus through active buttons and explicitly focusable
elements in draw order. Use `set_focusable` to include a label in that order
and `has_focus` to compose contextual UI around it.

In text fields, Ctrl or Option with Left/Right moves by word. Use the same
modifier with Backspace/Delete to delete by word, or add Shift to a movement
key to extend the selection. Ctrl+Up/Down moves between paragraphs. On macOS,
Command+Left/Right moves to the edge of the current line,
Command+Backspace/Delete deletes to that edge, and Command+Up/Down moves to
the beginning or end of the field.

Plain arrow movement and deletion respect grapheme boundaries, including
combining accents and joined emoji. Double-click selects a word and
triple-click selects a logical line. Drag after a multi-click to extend the
selection by the same unit. Multiline fields support wheel scrolling,
Page Up/Down, and vertical cursor movement that remembers its column.

Ctrl or Command+Z undoes an edit. Add Shift or use Ctrl or Command+Y to redo.
Adjacent keystrokes are grouped into a single edit. History records changes
accepted through `on_change` and starts fresh when the caller replaces the
field value independently. Input methods display composition inline and
propose the value when the operating system commits the text.
