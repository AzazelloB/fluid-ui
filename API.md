# Importing Fluid UI

The repository root is the engine package. It owns element IDs, geometry,
scenes, windows, input routing, and drawing primitives. The optional
`elements/` package builds reusable controls on that API. The standalone
showcase at `examples/showcase/` imports both packages and supplies its own
layout and presentation.

## Custom elements and styling

Use `fluid.create_element` with an `Element_Definition` to construct an
element directly. Set `pressable` for default click and keyboard activation,
or supply an `Element_Behavior` to process routed input with your own state.
The engine owns focus, pointer capture, and the lifetime of the element.
It calls `release_graphics` before invalidating renderer or font resources
and `destroy` when the element is removed.

Use `fluid.set_draw` to replace drawing on an engine element or a stock
control. The callback receives an `Element_View` with the current bounds,
text style, and interaction state. The Controls showcase paints the Name
field in application code and calls `elements.draw_field_text` to draw editing
content with app-specified placeholder, selection, and caret colors. Custom choice drawing can read `elements.choice_slots` and
`elements.choice_slot`, including drag previews. Custom confirmation drawing
can read `elements.confirmation_progress` for the animated fill.

# Units and geometry

All public lengths are plain `f32` values in UI units. One UI unit equals
16 logical points (`UI_UNIT_POINTS`). Pins, radii, text measurements, window
sizes and positions, and pointer coordinates use that unit. Display density is
handled at the SDL boundary.

## Pass values

`bounds` returns a struct of numeric edges. Widgets take the same struct:

```odin
viewport := fluid.bounds(ui, ui.window.viewport)
sidebar := elements.panel(scene, {
    left = viewport.right - 18.75,
    top = 1.5,
    right = viewport.right - 2.25,
    bottom = viewport.bottom - 1.5,
}, color)
```

There are no layout callbacks, stored expressions, or implicit references.
Changing `viewport` afterward does not change `sidebar`. To respond to resizing
or another element moving, calculate new values and send them again. Each demo
owns that work in its ordinary update handler.

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
Set `Style.hover_border` to draw a different border color while hovered.

## Windows

Bounds and pointer coordinates are window-local.
`transfer` preserves the element ID, animation progress, and size in UI units.
It rebases the element and animation origins to preserve their desktop positions.

`pointer_position`, `set_window_size`, and window configuration use UI units
scaled for the window's display. `window_position` and `set_window_position`
use shared desktop coordinates, expressed in SDL desktop units divided by
`UI_UNIT_POINTS`. Use `desktop_point` and `window_point` to convert between
these spaces. Multiply UI units by `window_scale(window)` for native SDL
window coordinates or by `pixel_scale(window)` for SDL renderer pixels.

## Direct controls

These constructors and value setters are in the optional `elements` package.
Choose a control according to the value or action it represents.

| Constructor | Interaction |
| --- | --- |
| `button` | Click or press Enter or Space to invoke its `on_press` callback. Use `.Secondary` for a text-first action. |
| `dangerous_button` | Hold for 750 ms or tap three times in quick succession. Progress clears after 500 ms of inactivity. A cancelled press earns no tap. |
| `toggle` | Flip a Boolean. Apply an accepted change with `fluid.set_selected`. |
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
