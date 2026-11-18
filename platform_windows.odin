package fluid

import "base:runtime"
import "core:strings"
import win "core:sys/windows"
import "core:time"
import vk "vendor:vulkan"

@(private="package")
Platform_Window :: struct {
	handle:       win.HWND,
	monitor:      win.HMONITOR,
	refresh_rate: u64,
	borderless:   bool,
	clip_frame_style: Maybe(u32),
	text_input:   bool,
	ime_area:     [4]i32,
	track_leave:  bool,
	surrogate:    u16,
	clicks:       u8,
	click_time:   u64,
	click_point:  win.POINT,
}

@(private="package")
platform_surface_extension : cstring : "VK_KHR_win32_surface"

@(private="file")
win_class_name := [?]u16{'F', 'l', 'u', 'i', 'd', 'W', 'i', 'n', 'd', 'o', 'w', 0}
@(private="file")
win_class := cstring16(&win_class_name[0])
@(private="file")
win_instance: win.HINSTANCE
@(private="file")
win_previous_dpi: win.DPI_AWARENESS_CONTEXT
@(private="file")
win_frame_timer: win.HANDLE
@(private="file")
win_cursors: [Cursor]win.HCURSOR
@(private="file")
win_cursor: Cursor
@(private="file")
win_events: [dynamic]Platform_Event
@(private="file")
win_event_index: int

foreign import imm "system:imm32.lib"
foreign import region_gdi "system:gdi32.lib"
foreign import window_user "system:user32.lib"
foreign import clipboard_kernel "system:kernel32.lib"

@(private="file")
Win_Composition_Form :: struct {
	style: win.DWORD,
	point: win.POINT,
	area:  win.RECT,
}

@(private="file")
Win_Candidate_Form :: struct {
	index: win.DWORD,
	style: win.DWORD,
	point: win.POINT,
	area:  win.RECT,
}

@(default_calling_convention="system", private="file")
foreign imm {
	ImmGetContext :: proc(hwnd: win.HWND) -> win.HANDLE ---
	ImmReleaseContext :: proc(hwnd: win.HWND, input: win.HANDLE) -> win.BOOL ---
	ImmAssociateContextEx :: proc(hwnd: win.HWND, input: win.HANDLE, flags: win.DWORD) -> win.BOOL ---
	ImmGetCompositionStringW :: proc(input: win.HANDLE, index: win.DWORD, buffer: rawptr, size: win.DWORD) -> win.LONG ---
	ImmNotifyIME :: proc(input: win.HANDLE, action, index, value: win.DWORD) -> win.BOOL ---
	ImmSetCompositionWindow :: proc(input: win.HANDLE, form: ^Win_Composition_Form) -> win.BOOL ---
	ImmSetCandidateWindow :: proc(input: win.HANDLE, form: ^Win_Candidate_Form) -> win.BOOL ---
}

@(default_calling_convention="system", private="file")
foreign region_gdi {
	CreateEllipticRgn :: proc(left, top, right, bottom: i32) -> win.HRGN ---
}

@(default_calling_convention="system", private="file")
foreign window_user {
	WindowFromPoint :: proc(point: win.POINT) -> win.HWND ---
	GetDoubleClickTime :: proc() -> win.UINT ---
	GetCurrentInputMessageSource :: proc(source: ^Win_Input_Message_Source) -> win.BOOL ---
}

@(private="file")
Win_Input_Message_Source :: struct {device, origin: u32}
@(private="file")
WIN_INPUT_TOUCHPAD :: 0x10

@(default_calling_convention="system", private="file")
foreign clipboard_kernel {
	GlobalSize :: proc(memory: win.HGLOBAL) -> win.SIZE_T ---
}

@(private="package")
platform_init :: proc() -> bool {
	win_instance = cast(win.HINSTANCE)win.GetModuleHandleW(nil)
	win_previous_dpi = win.SetThreadDpiAwarenessContext(win.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
	win_events = make([dynamic]Platform_Event, 0, 32)
	win_frame_timer = win.CreateWaitableTimerExW(nil, nil, win.CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
		win.TIMER_MODIFY_STATE | win.SYNCHRONIZE)
	win_cursors[.Default] = win.LoadCursorW(nil, transmute(win.LPCWSTR)win.IDC_ARROW)
	win_cursors[.Pointer] = win.LoadCursorW(nil, transmute(win.LPCWSTR)win.IDC_HAND)
	win_cursors[.Move] = win.LoadCursorW(nil, transmute(win.LPCWSTR)win.IDC_SIZEALL)
	win_cursors[.Text] = win.LoadCursorW(nil, transmute(win.LPCWSTR)win.IDC_IBEAM)
	win_cursors[.Resize_Horizontal] = win.LoadCursorW(nil, transmute(win.LPCWSTR)win.IDC_SIZEWE)
	class := win.WNDCLASSEXW{
		cbSize = size_of(win.WNDCLASSEXW),
		lpfnWndProc = win_window_proc,
		hInstance = win_instance,
		hCursor = win_cursors[.Default],
		lpszClassName = win_class,
	}
	if win.RegisterClassExW(&class) == 0 {
		platform_shutdown()
		return false
	}
	return true
}

@(private="package")
platform_shutdown :: proc() {
	release_win_text_rasterizer()
	if win_frame_timer != nil {
		win.CloseHandle(win_frame_timer)
		win_frame_timer = nil
	}
	win.UnregisterClassW(win_class, win_instance)
	if win_previous_dpi != nil {
		win.SetThreadDpiAwarenessContext(win_previous_dpi)
	}
	delete(win_events)
	win_events = nil
	win_event_index = 0
	win_previous_dpi = nil
	win_instance = nil
}

@(private="package")
platform_create_window :: proc(window: ^Window, config: Config) -> bool {
	title := win.utf8_to_wstring(string(config.title))
	style := win.WS_OVERLAPPEDWINDOW
	if .Borderless in config.flags {
		style = win.WS_POPUP | win.WS_THICKFRAME
		window.platform.borderless = true
	}
	mouse: win.POINT
	win.GetCursorPos(&mouse)
	monitor := win.MonitorFromPoint(mouse, .MONITOR_DEFAULTTONEAREST)
	work := win.MONITORINFO{cbSize = size_of(win.MONITORINFO)}
	if !win.GetMonitorInfoW(monitor, &work) {
		return false
	}
	area := work.rcWork
	handle := win.CreateWindowExW(0, win_class, title, style, area.left, area.top,
		1, 1, nil, nil, win_instance, window)
	if handle == nil {
		return false
	}
	window.platform.handle = handle
	use_dark_mode: win.BOOL = true
	win.DwmSetWindowAttribute(handle, win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE),
		&use_dark_mode, size_of(use_dark_mode))
	width, height := win_window_dimensions(window, {
		max(1, i32(config.size[0] * UI_UNIT_POINTS * win_dpi_scale(handle) + 0.5)),
		max(1, i32(config.size[1] * UI_UNIT_POINTS * win_dpi_scale(handle) + 0.5)),
	})
	center_x := area.left + (area.right - area.left - width) / 2
	center_y := area.top + (area.bottom - area.top - height) / 2
	ImmAssociateContextEx(handle, nil, 0)
	if !win.SetWindowPos(handle, nil, center_x, center_y, width, height, win.SWP_NOZORDER | win.SWP_NOACTIVATE) {
		platform_destroy_window(window)
		return false
	}
	return true
}

@(private="package")
platform_destroy_window :: proc(window: ^Window) {
	if window.platform.handle == nil {
		return
	}
	win.SetWindowLongPtrW(window.platform.handle, win.GWLP_USERDATA, 0)
	win.DestroyWindow(window.platform.handle)
	for i := len(win_events) - 1; i >= win_event_index; i -= 1 {
		if win_events[i].window == window {
			ordered_remove(&win_events, i)
		}
	}
	window.platform = {}
}

@(private="package")
platform_show_window :: proc(window: ^Window, show: bool) -> bool {
	command := win.SW_HIDE
	if show {
		command = window.ui.drag.element != NO_ELEMENT ? win.SW_SHOWNOACTIVATE : win.SW_SHOW
	}
	win.ShowWindow(window.platform.handle, command)
	return bool(win.IsWindowVisible(window.platform.handle)) == show
}

@(private="package")
platform_window_visible :: proc(window: ^Window) -> bool {
	handle := window.platform.handle
	return handle != nil && bool(win.IsWindowVisible(handle)) && !win.IsIconic(handle)
}

@(private="package")
platform_window_position :: proc(window: ^Window) -> [2]f32 {
	origin: win.POINT
	win.ClientToScreen(window.platform.handle, &origin)
	return {f32(origin.x), f32(origin.y)}
}

@(private="package")
platform_set_window_position :: proc(window: ^Window, position: [2]i32) -> bool {
	handle := window.platform.handle
	origin: win.POINT
	frame: win.RECT
	if !win.ClientToScreen(handle, &origin) || !win.GetWindowRect(handle, &frame) {
		return false
	}
	return bool(win.SetWindowPos(handle, nil, position[0] + frame.left - origin.x,
		position[1] + frame.top - origin.y, 0, 0, win.SWP_NOZORDER | win.SWP_NOSIZE | win.SWP_NOACTIVATE))
}

@(private="package")
platform_window_size :: proc(window: ^Window) -> [2]i32 {
	rect: win.RECT
	win.GetClientRect(window.platform.handle, &rect)
	return {rect.right, rect.bottom}
}

@(private="package")
platform_set_window_size :: proc(window: ^Window, size: [2]i32) -> bool {
	width, height := win_window_dimensions(window, size)
	return bool(win.SetWindowPos(window.platform.handle, nil, 0, 0, width, height,
		win.SWP_NOZORDER | win.SWP_NOMOVE | win.SWP_NOACTIVATE))
}

@(private="file")
win_window_dimensions :: proc(window: ^Window, size: [2]i32) -> (i32, i32) {
	if window.platform.borderless {
		return max(1, size[0]), max(1, size[1])
	}
	handle := window.platform.handle
	style := transmute(u32)win.GetWindowLongW(handle, win.GWL_STYLE)
	ex_style := transmute(u32)win.GetWindowLongW(handle, win.GWL_EXSTYLE)
	rect := win.RECT{right = max(1, size[0]), bottom = max(1, size[1])}
	win.AdjustWindowRectExForDpi(&rect, style, false, ex_style, max(96, win.GetDpiForWindow(handle)))
	return rect.right - rect.left, rect.bottom - rect.top
}

@(private="file")
win_dpi_scale :: proc(handle: win.HWND) -> f32 {
	dpi := win.GetDpiForWindow(handle)
	return dpi == 0 ? 1 : f32(dpi) / 96
}

@(private="package")
platform_window_scales :: proc(window: ^Window) -> (f32, f32) {
	scale := win_dpi_scale(window.platform.handle)
	return scale, scale
}

@(private="package")
platform_window_refresh_rate :: proc(window: ^Window) -> u64 {
	state := &window.platform
	monitor := win.MonitorFromWindow(state.handle, .MONITOR_DEFAULTTONEAREST)
	if monitor == state.monitor && state.refresh_rate > 0 {
		return state.refresh_rate
	}
	state.monitor = monitor
	state.refresh_rate = 60
	info: win.MONITORINFOEXW
	info.cbSize = size_of(win.MONITORINFOEXW)
	mode := win.DEVMODEW{dmSize = size_of(win.DEVMODEW)}
	if win.GetMonitorInfoW(monitor, cast(^win.MONITORINFO)&info) &&
	   win.EnumDisplaySettingsW(cstring16(&info.szDevice[0]), win.ENUM_CURRENT_SETTINGS, &mode) &&
	   mode.dmDisplayFrequency > 1 {
		state.refresh_rate = u64(mode.dmDisplayFrequency)
	}
	return state.refresh_rate
}

@(private="package")
platform_poll_event :: proc(app: ^UI) -> (Platform_Event, bool) {
	for {
		if win_event_index < len(win_events) {
			event := win_events[win_event_index]
			win_event_index += 1
			return event, true
		}
		clear(&win_events)
		win_event_index = 0
		msg: win.MSG
		if !win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
			return {}, false
		}
		if msg.message == win.WM_QUIT {
			return {kind = .Quit, timestamp = monotonic_ns()}, true
		}
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)
	}
}

@(private="file")
win_window_from_handle :: proc(handle: win.HWND) -> ^Window {
	if handle == nil {
		return nil
	}
	return cast(^Window)uintptr(win.GetWindowLongPtrW(handle, win.GWLP_USERDATA))
}

@(private="package")
platform_mouse_window :: proc(app: ^UI) -> ^Window {
	mouse: win.POINT
	if !win.GetCursorPos(&mouse) {
		return nil
	}
	handle := WindowFromPoint(mouse)
	// Only interpret user data for handles owned by Fluid.
	for window in app.windows {
		if window.platform.handle == handle {
			return window
		}
	}
	return nil
}

@(private="package")
platform_mouse_state :: proc() -> ([2]f32, bool) {
	mouse: win.POINT
	win.GetCursorPos(&mouse)
	return {f32(mouse.x), f32(mouse.y)}, win.GetAsyncKeyState(win.VK_LBUTTON) < 0
}

@(private="package")
platform_capture_mouse :: proc(window: ^Window) {
	if window != nil {
		win.SetCapture(window.platform.handle)
	} else if win.GetCapture() != nil {
		win.ReleaseCapture()
	}
}

@(private="package")
platform_set_cursor :: proc(app: ^UI, cursor: Cursor) {
	win_cursor = cursor
	if win.GetCapture() != nil {
		win.SetCursor(win_cursors[cursor])
		return
	}
	if window := platform_mouse_window(app); window != nil {
		point: win.POINT
		win.GetCursorPos(&point)
		win.ScreenToClient(window.platform.handle, &point)
		size := platform_window_size(window)
		if point.x >= 0 && point.y >= 0 && point.x < size[0] && point.y < size[1] {
			win.SetCursor(win_cursors[cursor])
		}
	}
}

@(private="file")
win_modifiers :: proc() -> Key_Modifiers {
	result: Key_Modifiers
	if win.GetKeyState(win.VK_SHIFT) < 0 { result += {.Shift} }
	if win.GetKeyState(win.VK_CONTROL) < 0 { result += {.Ctrl} }
	if win.GetKeyState(win.VK_MENU) < 0 { result += {.Alt} }
	if win.GetKeyState(win.VK_LWIN) < 0 || win.GetKeyState(win.VK_RWIN) < 0 { result += {.Gui} }
	return result
}

@(private="package")
platform_text_input :: proc(window: ^Window, enabled: bool) {
	if window.platform.text_input == enabled {
		return
	}
	window.platform.text_input = enabled
	window.platform.surrogate = 0
	window.platform.ime_area = {}
	if enabled {
		ImmAssociateContextEx(window.platform.handle, nil, 0x0010) // IACE_DEFAULT
	} else {
		platform_clear_composition(window)
		ImmAssociateContextEx(window.platform.handle, nil, 0)
	}
}

@(private="package")
platform_clear_composition :: proc(window: ^Window) {
	handle := window.platform.handle
	if input := ImmGetContext(handle); input != nil {
		ImmNotifyIME(input, 0x0015, 0x0004, 0) // NI_COMPOSITIONSTR, CPS_CANCEL
		ImmReleaseContext(handle, input)
	}
}

@(private="package")
platform_text_input_area :: proc(window: ^Window, area: [4]i32) {
	if window.platform.ime_area == area {
		return
	}
	window.platform.ime_area = area
	win_set_ime_area(window)
}

@(private="file")
win_set_ime_area :: proc(window: ^Window) {
	handle := window.platform.handle
	area := window.platform.ime_area
	if input := ImmGetContext(handle); input != nil {
		defer ImmReleaseContext(handle, input)
		composition := Win_Composition_Form{style = 0x0002, point = {area[0], area[1]}} // CFS_POINT
		ImmSetCompositionWindow(input, &composition)
		candidate := Win_Candidate_Form{
			style = 0x0080, // CFS_EXCLUDE
			point = {area[0], area[1] + area[3]},
			area = {area[0], area[1], area[0] + area[2], area[1] + area[3]},
		}
		ImmSetCandidateWindow(input, &candidate)
	}
}

@(private="package")
platform_clipboard_set :: proc(window: ^Window, value: string) -> bool {
	// CF_UNICODETEXT expects Windows line endings.
	text, _ := strings.replace_all(value, "\r\n", "\n", context.temp_allocator)
	text, _ = strings.replace_all(text, "\n", "\r\n", context.temp_allocator)
	wide := win.utf8_to_utf16(text)
	handle := cast(win.HGLOBAL)win.GlobalAlloc(0x0002, win.SIZE_T((len(wide) + 1) * size_of(u16))) // GMEM_MOVEABLE
	if handle == nil {
		return false
	}
	transferred := false
	defer if !transferred { win.GlobalFree(handle) }
	data := cast([^]u16)win.GlobalLock(handle)
	if data == nil {
		return false
	}
	copy(data[:len(wide)], wide)
	data[len(wide)] = 0
	win.GlobalUnlock(handle)
	if !win.OpenClipboard(window.platform.handle) {
		return false
	}
	defer win.CloseClipboard()
	if !win.EmptyClipboard() {
		return false
	}
	transferred = win.SetClipboardData(win.CF_UNICODETEXT, cast(win.HANDLE)handle) != nil
	return transferred
}

@(private="package")
platform_clipboard_get :: proc(window: ^Window) -> string {
	if !win.OpenClipboard(window.platform.handle) {
		return ""
	}
	defer win.CloseClipboard()
	handle := cast(win.HGLOBAL)win.GetClipboardData(win.CF_UNICODETEXT)
	if handle == nil {
		return ""
	}
	data := cast([^]u16)win.GlobalLock(handle)
	if data == nil {
		return ""
	}
	defer win.GlobalUnlock(handle)
	size := int(GlobalSize(handle)) / size_of(u16)
	length := 0
	for length < size && data[length] != 0 {
		length += 1
	}
	value := win.utf16_to_utf8(data[:length]) or_else ""
	text, _ := strings.replace_all(value, "\r\n", "\n", context.temp_allocator)
	return text
}

@(private="package")
platform_create_surface :: proc(window: ^Window, instance: vk.Instance) -> (vk.SurfaceKHR, vk.Result) {
	info := vk.Win32SurfaceCreateInfoKHR{
		sType = .WIN32_SURFACE_CREATE_INFO_KHR,
		hinstance = win_instance,
		hwnd = window.platform.handle,
	}
	surface: vk.SurfaceKHR
	result := vk.CreateWin32SurfaceKHR(instance, &info, nil, &surface)
	return surface, result
}

@(private="package")
platform_clips_drawable :: false

@(private="package")
platform_set_window_clip :: proc(window: ^Window, circle: Maybe(Window_Circle)) -> bool {
	state := &window.platform
	handle := state.handle
	shape, clipped := circle.?
	if !clipped {
		if state.clip_frame_style == nil {
			return true
		}
		if win.SetWindowRgn(handle, nil, false) == 0 {
			return false
		}
		return win_set_clip_frame(window, false)
	}

	scale := window_scale(window)
	x, y := i32(shape.center[0] * scale), i32(shape.center[1] * scale)
	radius := i32(shape.radius * scale + 0.5)
	region := CreateEllipticRgn(x - radius, y - radius, x + radius, y + radius)
	if region == nil {
		return false
	}
	first_clip := state.clip_frame_style == nil
	if first_clip && !win_set_clip_frame(window, true) {
		win.DeleteObject(cast(win.HGDIOBJ)region)
		return false
	}
	if win.SetWindowRgn(handle, region, true) != 0 {
		return true // Windows owns the region after a successful call.
	}
	win.DeleteObject(cast(win.HGDIOBJ)region)
	if first_clip {
		_ = win_set_clip_frame(window, false)
	}
	return false
}

@(private="file")
win_set_clip_frame :: proc(window: ^Window, clipped: bool) -> bool {
	state := &window.platform
	handle := state.handle
	client: win.RECT
	origin: win.POINT
	if !win.GetClientRect(handle, &client) || !win.ClientToScreen(handle, &origin) {
		return false
	}
	previous := state.clip_frame_style
	FRAME_STYLE :: win.WS_OVERLAPPEDWINDOW | win.WS_POPUP
	old_style := transmute(u32)win.GetWindowLongW(handle, win.GWL_STYLE)
	style := old_style & ~FRAME_STYLE
	if clipped {
		style |= win.WS_POPUP
	} else {
		style |= previous.?
		if !state.borderless {
			ex_style := transmute(u32)win.GetWindowLongW(handle, win.GWL_EXSTYLE)
			if !win.AdjustWindowRectExForDpi(&client, style, false, ex_style, max(96, win.GetDpiForWindow(handle))) {
				return false
			}
		}
	}
	if win.SetWindowLongW(handle, win.GWL_STYLE, transmute(win.LONG)style) == 0 {
		return false
	}
	if clipped {
		state.clip_frame_style = old_style & FRAME_STYLE
	} else {
		state.clip_frame_style = nil
	}
	// A region disables modern non-client rendering. Suppress the frame while
	// clipped so Windows has no classic caption or outline to paint.
	win_set_clip_chrome(handle, clipped)
	if win.SetWindowPos(handle, nil, origin.x + client.left, origin.y + client.top,
		client.right - client.left, client.bottom - client.top,
		win.SWP_FRAMECHANGED | win.SWP_NOZORDER | win.SWP_NOACTIVATE) {
		return true
	}
	state.clip_frame_style = previous
	win.SetWindowLongW(handle, win.GWL_STYLE, transmute(win.LONG)old_style)
	win_set_clip_chrome(handle, previous != nil)
	return false
}

@(private="file")
win_set_clip_chrome :: proc(handle: win.HWND, clipped: bool) {
	policy := clipped ? win.DWMNCRENDERINGPOLICY.DWMNCRP_DISABLED : .DWMNCRP_USEWINDOWSTYLE
	border_color: u32 = clipped ? 0xfffffffe : 0xffffffff // DWMWA_COLOR_NONE and DWMWA_COLOR_DEFAULT.
	win.DwmSetWindowAttribute(handle, win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_NCRENDERING_POLICY), &policy, size_of(policy))
	win.DwmSetWindowAttribute(handle, win.DWORD(win.DWMWINDOWATTRIBUTE.DWMWA_BORDER_COLOR), &border_color, size_of(border_color))
}

@(private="file")
win_window_proc :: proc "system" (
	handle: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM,
) -> win.LRESULT {
	context = runtime.default_context()
	if message == win.WM_NCCREATE {
		params := cast(^win.CREATESTRUCTW)uintptr(lparam)
		win.SetWindowLongPtrW(handle, win.GWLP_USERDATA, win.LONG_PTR(cast(uintptr)params.lpCreateParams))
		return win.DefWindowProcW(handle, message, wparam, lparam)
	}
	window := win_window_from_handle(handle)
	if window == nil {
		return win.DefWindowProcW(handle, message, wparam, lparam)
	}
	event := Platform_Event{window = window, timestamp = monotonic_ns()}
	switch message {
	case win.WM_NCPAINT:
		if window.platform.clip_frame_style != nil {
			return 0
		}
		return win.DefWindowProcW(handle, message, wparam, lparam)
	case win.WM_NCCALCSIZE:
		if window.platform.borderless {
			return 0
		}
		return win.DefWindowProcW(handle, message, wparam, lparam)
	case win.WM_NCHITTEST:
		if window.platform.borderless {
			return win_borderless_hit(window, lparam)
		}
		return win.DefWindowProcW(handle, message, wparam, lparam)
	case win.WM_CLOSE:
		event.kind = .Close
	case win.WM_ERASEBKGND:
		// Vulkan clears the client area.
		return 1
	case win.WM_SIZE:
		event.kind = .Resize
	case win.WM_DISPLAYCHANGE:
		window.platform.refresh_rate = 0
		return win.DefWindowProcW(handle, message, wparam, lparam)
	case win.WM_DPICHANGED:
		rect := cast(^win.RECT)uintptr(lparam)
		win.SetWindowPos(handle, nil, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top,
			win.SWP_NOZORDER | win.SWP_NOACTIVATE)
		event.kind = .Resize
	case win.WM_GETMINMAXINFO:
		size := window.minimum_size * (UI_UNIT_POINTS * win_dpi_scale(handle))
		width, height := win_window_dimensions(window, {i32(size[0] + 0.5), i32(size[1] + 0.5)})
		limits := cast(^win.MINMAXINFO)uintptr(lparam)
		limits.ptMinTrackSize.x = max(limits.ptMinTrackSize.x, width)
		limits.ptMinTrackSize.y = max(limits.ptMinTrackSize.y, height)
		return 0
	case win.WM_KILLFOCUS:
		event.kind = .Focus_Lost
		window.platform.surrogate = 0
	case win.WM_MOUSELEAVE:
		event.kind = .Mouse_Leave
		window.platform.track_leave = false
	case win.WM_MOUSEMOVE:
		event.kind = .Mouse_Move
		event.position = {f32(win.GET_X_LPARAM(lparam)), f32(win.GET_Y_LPARAM(lparam))}
		if !window.platform.track_leave {
			tracking := win.TRACKMOUSEEVENT{cbSize = size_of(win.TRACKMOUSEEVENT), dwFlags = win.TME_LEAVE, hwndTrack = handle}
			window.platform.track_leave = bool(win.TrackMouseEvent(&tracking))
		}
	case win.WM_LBUTTONDOWN:
		event.kind = .Mouse_Down
		event.modifiers = win_modifiers()
		point := win.POINT{win.GET_X_LPARAM(lparam), win.GET_Y_LPARAM(lparam)}
		event.position = {f32(point.x), f32(point.y)}
		event.clicks = win_click_count(window, point, event.timestamp)
	case win.WM_LBUTTONUP:
		event.kind = .Mouse_Up
		event.position = {f32(win.GET_X_LPARAM(lparam)), f32(win.GET_Y_LPARAM(lparam))}
	case win.WM_MOUSEWHEEL:
		event.kind = .Wheel
		point := win.POINT{win.GET_X_LPARAM(lparam), win.GET_Y_LPARAM(lparam)}
		win.ScreenToClient(handle, &point)
		event.position = {f32(point.x), f32(point.y)}
		event.wheel = f32(win.GET_WHEEL_DELTA_WPARAM(wparam)) / win.WHEEL_DELTA
		source: Win_Input_Message_Source
		event.wheel_direct = bool(GetCurrentInputMessageSource(&source)) && source.device == WIN_INPUT_TOUCHPAD
	case win.WM_SETCURSOR:
		if u16(lparam & 0xffff) == win.HTCLIENT {
			win.SetCursor(win_cursors[win_cursor])
			return 1
		}
		return win.DefWindowProcW(handle, message, wparam, lparam)
	case win.WM_SYSKEYDOWN, win.WM_SYSKEYUP:
		// Alt+F4, Alt+Tab, and native menu commands belong to Windows.
		if wparam == win.VK_F4 || wparam == win.VK_TAB || wparam == win.VK_SPACE {
			return win.DefWindowProcW(handle, message, wparam, lparam)
		}
		fallthrough
	case win.WM_KEYDOWN, win.WM_KEYUP:
		key := win_key(wparam, lparam)
		if key == .Unknown {
			return win.DefWindowProcW(handle, message, wparam, lparam)
		}
		event.kind = .Key
		event.key = {
			key = key, modifiers = win_modifiers(), timestamp = event.timestamp,
			down = message == win.WM_KEYDOWN || message == win.WM_SYSKEYDOWN,
			repeat = lparam & (1 << 30) != 0,
		}
	case win.WM_CHAR, win.WM_IME_CHAR:
		if window.platform.text_input && wparam >= 0x20 && wparam != 0x7f {
			win_emit_u16(window, u16(wparam), event.timestamp)
		}
		return 0
	case win.WM_IME_SETCONTEXT:
		// Fluid draws the composition in its editor. Leave native candidate UI enabled.
		return win.DefWindowProcW(handle, message, wparam, lparam & ~win.LPARAM(0x80000000))
	case win.WM_IME_STARTCOMPOSITION:
		if window.platform.text_input {
			win_set_ime_area(window)
			return 0
		}
		return win.DefWindowProcW(handle, message, wparam, lparam)
	case win.WM_IME_COMPOSITION:
		if window.platform.text_input { win_emit_composition(window, win.DWORD(lparam), event.timestamp); return 0 }
		return win.DefWindowProcW(handle, message, wparam, lparam)
	case win.WM_IME_ENDCOMPOSITION:
		if !window.platform.text_input { return 0 }
		event.kind = .Text_Edit
	case:
		return win.DefWindowProcW(handle, message, wparam, lparam)
	}
	append(&win_events, event)
	return 0
}

@(private="file")
win_borderless_hit :: proc(window: ^Window, lparam: win.LPARAM) -> win.LRESULT {
	handle := window.platform.handle
	rect: win.RECT
	win.GetWindowRect(handle, &rect)
	x, y := win.GET_X_LPARAM(lparam), win.GET_Y_LPARAM(lparam)
	dpi := win.GetDpiForWindow(handle)
	border_x := win.GetSystemMetricsForDpi(32, dpi) // SM_CXSIZEFRAME
	border_y := win.GetSystemMetricsForDpi(33, dpi) // SM_CYSIZEFRAME
	left, right := x < rect.left + border_x, x >= rect.right - border_x
	top, bottom := y < rect.top + border_y, y >= rect.bottom - border_y
	if top {
		if left { return win.HTTOPLEFT }
		if right { return win.HTTOPRIGHT }
		return win.HTTOP
	}
	if bottom {
		if left { return win.HTBOTTOMLEFT }
		if right { return win.HTBOTTOMRIGHT }
		return win.HTBOTTOM
	}
	if left { return win.HTLEFT }
	if right { return win.HTRIGHT }
	return win.HTCLIENT
}

@(private="file")
win_click_count :: proc(window: ^Window, point: win.POINT, now: u64) -> u8 {
	state := &window.platform
	dpi := win.GetDpiForWindow(state.handle)
	dx := win.GetSystemMetricsForDpi(36, dpi) / 2 // SM_CXDOUBLECLK
	dy := win.GetSystemMetricsForDpi(37, dpi) / 2 // SM_CYDOUBLECLK
	if now - state.click_time <= u64(GetDoubleClickTime()) * 1_000_000 &&
	   abs(point.x - state.click_point.x) <= dx && abs(point.y - state.click_point.y) <= dy {
		state.clicks = min(3, state.clicks + 1)
	} else {
		state.clicks = 1
	}
	state.click_time = now
	state.click_point = point
	return state.clicks
}

@(private="file")
win_key :: proc(wparam: win.WPARAM, lparam: win.LPARAM) -> Key {
	if 'A' <= wparam && wparam <= 'Z' {
		return Key(int(Key.A) + int(wparam - 'A'))
	}
	if '0' <= wparam && wparam <= '9' {
		return Key(int(Key.Digit_0) + int(wparam - '0'))
	}
	if win.VK_NUMPAD0 <= wparam && wparam <= win.VK_NUMPAD9 {
		return Key(int(Key.Digit_0) + int(wparam - win.VK_NUMPAD0))
	}
	if win.VK_F1 <= wparam && wparam <= win.VK_F12 {
		return Key(int(Key.F1) + int(wparam - win.VK_F1))
	}
	switch wparam {
	case win.VK_BACK: return .Backspace
	case win.VK_DELETE: return .Delete
	case win.VK_DOWN: return .Down
	case win.VK_END: return .End
	case win.VK_ESCAPE: return .Escape
	case win.VK_HOME: return .Home
	case win.VK_INSERT: return .Insert
	case win.VK_RETURN: return lparam & (1 << 24) != 0 ? .Keypad_Enter : .Enter
	case win.VK_LEFT: return .Left
	case win.VK_NEXT: return .Page_Down
	case win.VK_PRIOR: return .Page_Up
	case win.VK_RIGHT: return .Right
	case win.VK_SPACE: return .Space
	case win.VK_TAB: return .Tab
	case win.VK_UP: return .Up
	}
	return .Unknown
}

@(private="file")
win_emit_u16 :: proc(window: ^Window, value: u16, timestamp: u64) {
	if 0xd800 <= value && value <= 0xdbff {
		window.platform.surrogate = value
		return
	}
	pair := [2]u16{window.platform.surrogate, value}
	window.platform.surrogate = 0
	length := (0xdc00 <= value && value <= 0xdfff && pair[0] != 0) ? 2 : 1
	text := win.utf16_to_utf8(pair[2-length:]) or_else ""
	if text != "" {
		append(&win_events, Platform_Event{kind = .Text_Input, window = window, timestamp = timestamp, text = {text}})
	}
}

@(private="file")
win_composition_text :: proc(input: win.HANDLE, index: win.DWORD) -> []u16 {
	size := ImmGetCompositionStringW(input, index, nil, 0)
	if size <= 0 {
		return nil
	}
	data := make([]u16, size / size_of(u16), context.temp_allocator)
	read := ImmGetCompositionStringW(input, index, raw_data(data), win.DWORD(size))
	return data[:clamp(int(read) / size_of(u16), 0, len(data))]
}

@(private="file")
win_emit_composition :: proc(window: ^Window, flags: win.DWORD, timestamp: u64) {
	handle := window.platform.handle
	input := ImmGetContext(handle)
	if input == nil { return }
	defer ImmReleaseContext(handle, input)
	COMPOSITION_STRING :: 0x0008
	CURSOR_POSITION :: 0x0080
	RESULT_STRING :: 0x0800
	if flags & RESULT_STRING != 0 {
		text := win.utf16_to_utf8(win_composition_text(input, RESULT_STRING)) or_else ""
		append(&win_events, Platform_Event{kind = .Text_Input, window = window, timestamp = timestamp, text = {text}})
	}
	if flags & (COMPOSITION_STRING | CURSOR_POSITION) != 0 || flags == 0 {
		wide := win_composition_text(input, COMPOSITION_STRING)
		text := win.utf16_to_utf8(wide) or_else ""
		caret := ImmGetCompositionStringW(input, CURSOR_POSITION, nil, 0)
		start := max(0, min(int(caret), len(wide)))
		for value in wide[:start] {
			if 0xdc00 <= value && value <= 0xdfff { start -= 1 }
		}
		append(&win_events, Platform_Event{kind = .Text_Edit, window = window, timestamp = timestamp,
			edit = {text = text, start = i32(start)}})
	}
}

@(private="package")
platform_wait_frame :: proc(nanoseconds: u64) {
	if win_frame_timer != nil {
		due := -win.LARGE_INTEGER(max(1, (nanoseconds + 99) / 100))
		if win.SetWaitableTimerEx(win_frame_timer, &due, 0, nil, nil, nil, 0) {
			win.WaitForSingleObject(win_frame_timer, win.INFINITE)
			return
		}
	}
	time.sleep(time.Duration(nanoseconds))
}
