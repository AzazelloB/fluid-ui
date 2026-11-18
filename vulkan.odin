package fluid

import "base:runtime"
import "core:dynlib"
import "core:fmt"
import vk "vendor:vulkan"

@(private="package")
Vulkan :: struct {
	library: dynlib.Library,
	instance: vk.Instance,
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	queue_family: u32,
	queue: vk.Queue,
	memory: vk.PhysicalDeviceMemoryProperties,
	mask_limit: int,
	surface_maintenance, swapchain_maintenance: bool,
	set_layout: vk.DescriptorSetLayout,
	pipeline_layout: vk.PipelineLayout,
}

Renderer :: struct {
	vulkan: ^Vulkan,
	surface: vk.SurfaceKHR,
	transparent: bool,
	failed: bool,
	swapchain: vk.SwapchainKHR,
	images: []Swap_Image,
	format: vk.Format,
	render_pass: vk.RenderPass,
	pipeline: vk.Pipeline,
	shader_pipelines: map[Shader_Code]vk.Pipeline,
	present_mode: vk.PresentModeKHR,
	extent: vk.Extent2D,
	requested_size: [2]i32,
	recreate: bool,
	command_pool: vk.CommandPool,
	descriptor_pool: vk.DescriptorPool,
	frames: [FRAMES_IN_FLIGHT]Render_Frame,
	frame_index: int,
	clip: IRect,
	recording: bool,
	vertices: [dynamic]Draw_Vertex,
	indices: [dynamic]u32,
	masks: [dynamic]u8,
	batches: [dynamic]Draw_Batch,
}

@(private="file")
Frame_Constants :: struct {
	scale: [2]f32,
	circle_center: [2]f32,
	circle_radius_squared: f32,
	clip_enabled: u32,
	_padding: [2]u32,
	shader: Shader_Constants,
}

@(private="file")
Shader_Code :: struct {
	words: ^u32,
	length: int,
}

@(private="package")
Shader_Draw :: struct {
	pipeline: vk.Pipeline,
	constants: Shader_Constants,
}

@(private="package")
Shader_Constants :: struct {
	rect, data: [4]f32,
}

#assert(offset_of(Frame_Constants, shader) == 32)
#assert(size_of(Frame_Constants) == 64)

@(private="file")
FRAMES_IN_FLIGHT :: 2

@(private="file")
Mapped_Buffer :: struct {
	handle: vk.Buffer,
	memory: vk.DeviceMemory,
	data: rawptr,
	size: int,
}

@(private="file")
Render_Frame :: struct {
	acquired: vk.Semaphore,
	completed: vk.Fence,
	command: vk.CommandBuffer,
	descriptor: vk.DescriptorSet,
	geometry, masks: Mapped_Buffer,
}

@(private="file")
Swap_Image :: struct {
	view: vk.ImageView,
	framebuffer: vk.Framebuffer,
	// Waiting for acquisition of this image also completes the previous presentation wait.
	ready: vk.Semaphore,
	present_fence: vk.Fence,
	present_pending: bool,
}

@(private="package")
vulkan_init :: proc(v: ^Vulkan) -> bool {
	when ODIN_OS == .Windows {
		libraries := [?]string{"vulkan-1.dll"}
	} else when ODIN_OS == .Darwin {
		libraries := [?]string{
			"libvulkan.1.dylib", "/opt/homebrew/lib/libvulkan.1.dylib", "/usr/local/lib/libvulkan.1.dylib",
			"libMoltenVK.dylib", "/opt/homebrew/lib/libMoltenVK.dylib", "/usr/local/lib/libMoltenVK.dylib",
		}
	}
	for name in libraries {
		if library, loaded := dynlib.load_library(name); loaded {
			v.library = library
			break
		}
	}
	if v.library == nil {
		fmt.eprintln("Cannot load Vulkan. Install a Vulkan-capable graphics driver or MoltenVK on macOS.")
		return false
	}
	entry := dynlib.symbol_address(v.library, "vkGetInstanceProcAddr")
	if entry == nil {
		fmt.eprintln("The Vulkan library does not export vkGetInstanceProcAddr.")
		return false
	}
	vk.load_proc_addresses(entry)
	available_count: u32
	if !vulkan_ok(vk.EnumerateInstanceExtensionProperties(nil, &available_count, nil), "enumerate instance extensions") {
		return false
	}
	available := make([]vk.ExtensionProperties, int(available_count), context.temp_allocator)
	if !vulkan_ok(vk.EnumerateInstanceExtensionProperties(nil, &available_count, raw_data(available)), "read instance extensions") {
		return false
	}
	names := [6]cstring{"VK_KHR_surface", platform_surface_extension, nil, nil, nil, nil}
	count: u32 = 2
	flags: vk.InstanceCreateFlags
	when ODIN_OS == .Darwin {
		if vulkan_extension(available, "VK_KHR_portability_enumeration") {
			flags = {.ENUMERATE_PORTABILITY_KHR}
			names[count] = "VK_KHR_portability_enumeration"
			count += 1
		}
	}
	properties2 := vulkan_extension(available, "VK_KHR_get_physical_device_properties2")
	if properties2 {
		names[count] = "VK_KHR_get_physical_device_properties2"
		count += 1
	}
	if properties2 && vulkan_extension(available, "VK_KHR_surface_maintenance1") &&
		vulkan_extension(available, "VK_KHR_get_surface_capabilities2") {
		names[count] = "VK_KHR_get_surface_capabilities2"
		names[count + 1] = "VK_KHR_surface_maintenance1"
		count += 2
		v.surface_maintenance = true
	}
	application := vk.ApplicationInfo{
		sType = .APPLICATION_INFO, pApplicationName = "Fluid UI", apiVersion = vk.API_VERSION_1_0,
	}
	info := vk.InstanceCreateInfo{
		sType = .INSTANCE_CREATE_INFO, flags = flags, pApplicationInfo = &application,
		enabledExtensionCount = count, ppEnabledExtensionNames = raw_data(names[:]),
	}
	if !vulkan_ok(vk.CreateInstance(&info, nil, &v.instance), "create instance") {
		return false
	}
	vk.load_proc_addresses(v.instance)
	return true
}

@(private="package")
vulkan_shutdown :: proc(v: ^Vulkan) {
	vulkan_close_device(v)
	if v.instance != nil {
		vk.DestroyInstance(v.instance, nil)
	}
	if v.library != nil {
		dynlib.unload_library(v.library)
	}
	v^ = {}
}

@(private="file")
vulkan_close_device :: proc(v: ^Vulkan) {
	if v.device == nil {
		return
	}
	vk.DeviceWaitIdle(v.device)
	vk.DestroyPipelineLayout(v.device, v.pipeline_layout, nil)
	vk.DestroyDescriptorSetLayout(v.device, v.set_layout, nil)
	vk.DestroyDevice(v.device, nil)
	v.device, v.physical_device, v.queue = nil, nil, nil
	v.set_layout, v.pipeline_layout = 0, 0
	v.swapchain_maintenance = false
}

@(private="file")
vulkan_open_device :: proc(v: ^Vulkan, surface: vk.SurfaceKHR) -> bool {
	if v.device != nil {
		supported: b32
		return vulkan_ok(vk.GetPhysicalDeviceSurfaceSupportKHR(v.physical_device, v.queue_family, surface, &supported),
			"query presentation support") && bool(supported)
	}
	count: u32
	if !vulkan_ok(vk.EnumeratePhysicalDevices(v.instance, &count, nil), "enumerate physical devices") {
		return false
	}
	devices := make([]vk.PhysicalDevice, int(count), context.temp_allocator)
	if !vulkan_ok(vk.EnumeratePhysicalDevices(v.instance, &count, raw_data(devices)), "read physical devices") {
		return false
	}
	for physical_device in devices[:count] {
		extension_count: u32
		if vk.EnumerateDeviceExtensionProperties(physical_device, nil, &extension_count, nil) != .SUCCESS {
			continue
		}
		extensions := make([]vk.ExtensionProperties, int(extension_count), context.temp_allocator)
		if vk.EnumerateDeviceExtensionProperties(physical_device, nil, &extension_count, raw_data(extensions)) != .SUCCESS ||
			!vulkan_extension(extensions[:extension_count], "VK_KHR_swapchain") {
			continue
		}
		family, supported := vulkan_present_queue(physical_device, surface)
		if !supported {
			continue
		}
		names := [3]cstring{"VK_KHR_swapchain", nil, nil}
		name_count: u32 = 1
		if vulkan_extension(extensions[:extension_count], "VK_KHR_portability_subset") {
			names[name_count] = "VK_KHR_portability_subset"
			name_count += 1
		}
		maintenance := vk.PhysicalDeviceSwapchainMaintenance1FeaturesKHR{
			sType = .PHYSICAL_DEVICE_SWAPCHAIN_MAINTENANCE_1_FEATURES_KHR,
		}
		if v.surface_maintenance && vulkan_extension(extensions[:extension_count], "VK_KHR_swapchain_maintenance1") {
			features := vk.PhysicalDeviceFeatures2{sType = .PHYSICAL_DEVICE_FEATURES_2, pNext = &maintenance}
			vk.GetPhysicalDeviceFeatures2KHR(physical_device, &features)
			if maintenance.swapchainMaintenance1 {
				names[name_count] = "VK_KHR_swapchain_maintenance1"
				name_count += 1
			}
		}
		priority: f32 = 1
		queue_info := vk.DeviceQueueCreateInfo{
			sType = .DEVICE_QUEUE_CREATE_INFO, queueFamilyIndex = family, queueCount = 1, pQueuePriorities = &priority,
		}
		create := vk.DeviceCreateInfo{
			sType = .DEVICE_CREATE_INFO, queueCreateInfoCount = 1, pQueueCreateInfos = &queue_info,
			enabledExtensionCount = name_count, ppEnabledExtensionNames = raw_data(names[:]),
		}
		if maintenance.swapchainMaintenance1 {
			create.pNext = &maintenance
		}
		if !vulkan_ok(vk.CreateDevice(physical_device, &create, nil, &v.device), "create graphics device") {
			continue
		}
		v.physical_device = physical_device
		v.queue_family = family
		v.swapchain_maintenance = bool(maintenance.swapchainMaintenance1)
		break
	}
	if v.device == nil {
		fmt.eprintln("Vulkan did not find a graphics device that can present to this window.")
		return false
	}
	vk.load_proc_addresses(v.device)
	ready := false
	defer if !ready { vulkan_close_device(v) }
	vk.GetDeviceQueue(v.device, v.queue_family, 0, &v.queue)
	vk.GetPhysicalDeviceMemoryProperties(v.physical_device, &v.memory)
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(v.physical_device, &properties)
	v.mask_limit = int(properties.limits.maxStorageBufferRange)
	binding := vk.DescriptorSetLayoutBinding{
		binding = 0, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, stageFlags = {.FRAGMENT},
	}
	set_info := vk.DescriptorSetLayoutCreateInfo{
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO, bindingCount = 1, pBindings = &binding,
	}
	if !vulkan_ok(vk.CreateDescriptorSetLayout(v.device, &set_info, nil, &v.set_layout), "create mask descriptor layout") {
		return false
	}
	push := vk.PushConstantRange{stageFlags = {.VERTEX, .FRAGMENT}, size = size_of(Frame_Constants)}
	pipeline_info := vk.PipelineLayoutCreateInfo{
		sType = .PIPELINE_LAYOUT_CREATE_INFO, setLayoutCount = 1, pSetLayouts = &v.set_layout,
		pushConstantRangeCount = 1, pPushConstantRanges = &push,
	}
	ready = vulkan_ok(vk.CreatePipelineLayout(v.device, &pipeline_info, nil, &v.pipeline_layout), "create pipeline layout")
	return ready
}

@(private="file")
vulkan_present_queue :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (u32, bool) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)
	families := make([]vk.QueueFamilyProperties, int(count), context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))
	for family, i in families[:count] {
		if family.queueCount == 0 || .GRAPHICS not_in family.queueFlags {
			continue
		}
		supported: b32
		if vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported) == .SUCCESS && supported {
			return u32(i), true
		}
	}
	return 0, false
}

@(private="file")
vulkan_extension :: proc(extensions: []vk.ExtensionProperties, name: string) -> bool {
	for &extension in extensions {
		if string(cstring(raw_data(extension.extensionName[:]))) == name {
			return true
		}
	}
	return false
}

@(private="file")
vulkan_ok :: proc(result: vk.Result, operation: string) -> bool {
	if result != .SUCCESS {
		fmt.eprintln("Vulkan could not", operation, "(", result, ")")
		return false
	}
	return true
}

@(private="package")
renderer_init :: proc(r: ^Renderer, v: ^Vulkan, surface: vk.SurfaceKHR, transparent: bool) -> bool {
	r^ = {vulkan = v, surface = surface, transparent = transparent}
	success := false
	defer if !success { renderer_destroy(r) }
	if !vulkan_open_device(v, surface) {
		return false
	}
	r.vertices = make([dynamic]Draw_Vertex, runtime.heap_allocator())
	r.indices = make([dynamic]u32, runtime.heap_allocator())
	r.masks = make([dynamic]u8, runtime.heap_allocator())
	r.batches = make([dynamic]Draw_Batch, runtime.heap_allocator())
	pool := vk.CommandPoolCreateInfo{
		sType = .COMMAND_POOL_CREATE_INFO, queueFamilyIndex = v.queue_family, flags = {.RESET_COMMAND_BUFFER},
	}
	if !vulkan_ok(vk.CreateCommandPool(v.device, &pool, nil, &r.command_pool), "create command pool") {
		return false
	}
	command_info := vk.CommandBufferAllocateInfo{
		sType = .COMMAND_BUFFER_ALLOCATE_INFO, commandPool = r.command_pool,
		level = .PRIMARY, commandBufferCount = FRAMES_IN_FLIGHT,
	}
	commands: [FRAMES_IN_FLIGHT]vk.CommandBuffer
	if !vulkan_ok(vk.AllocateCommandBuffers(v.device, &command_info, raw_data(commands[:])), "allocate command buffers") {
		return false
	}
	pool_size := vk.DescriptorPoolSize{type = .STORAGE_BUFFER, descriptorCount = FRAMES_IN_FLIGHT}
	descriptor_info := vk.DescriptorPoolCreateInfo{
		sType = .DESCRIPTOR_POOL_CREATE_INFO, maxSets = FRAMES_IN_FLIGHT, poolSizeCount = 1, pPoolSizes = &pool_size,
	}
	if !vulkan_ok(vk.CreateDescriptorPool(v.device, &descriptor_info, nil, &r.descriptor_pool), "create descriptor pool") {
		return false
	}
	sets: [FRAMES_IN_FLIGHT]vk.DescriptorSet
	layouts := [FRAMES_IN_FLIGHT]vk.DescriptorSetLayout{v.set_layout, v.set_layout}
	set_info := vk.DescriptorSetAllocateInfo{
		sType = .DESCRIPTOR_SET_ALLOCATE_INFO, descriptorPool = r.descriptor_pool,
		descriptorSetCount = FRAMES_IN_FLIGHT, pSetLayouts = raw_data(layouts[:]),
	}
	if !vulkan_ok(vk.AllocateDescriptorSets(v.device, &set_info, raw_data(sets[:])), "allocate mask descriptors") {
		return false
	}
	semaphore := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
	fence := vk.FenceCreateInfo{sType = .FENCE_CREATE_INFO, flags = {.SIGNALED}}
	for &frame, i in r.frames {
		frame.command = commands[i]
		frame.descriptor = sets[i]
		if !vulkan_ok(vk.CreateSemaphore(v.device, &semaphore, nil, &frame.acquired), "create acquisition semaphore") ||
			!vulkan_ok(vk.CreateFence(v.device, &fence, nil, &frame.completed), "create frame fence") {
			return false
		}
	}
	success = true
	return true
}

@(private="package")
renderer_destroy :: proc(r: ^Renderer) {
	if r.vulkan == nil {
		return
	}
	v := r.vulkan
	if v.device != nil {
		vk.DeviceWaitIdle(v.device)
		release_swapchain(r)
		release_pipeline(r)
		vk.DestroyCommandPool(v.device, r.command_pool, nil)
		vk.DestroyDescriptorPool(v.device, r.descriptor_pool, nil)
		for &frame in r.frames {
			vk.DestroyFence(v.device, frame.completed, nil)
			vk.DestroySemaphore(v.device, frame.acquired, nil)
			release_buffer(v.device, &frame.geometry)
			release_buffer(v.device, &frame.masks)
		}
	}
	if r.surface != 0 {
		vk.DestroySurfaceKHR(v.instance, r.surface, nil)
	}
	delete(r.vertices)
	delete(r.indices)
	delete(r.masks)
	delete(r.batches)
	r^ = {}
}

@(private="file")
release_swapchain :: proc(r: ^Renderer) {
	device := r.vulkan.device
	for &image in r.images {
		if image.present_pending {
			vulkan_ok(vk.WaitForFences(device, 1, &image.present_fence, true, max(u64)), "finish swapchain presentation")
		}
		vk.DestroyFence(device, image.present_fence, nil)
		vk.DestroyFramebuffer(device, image.framebuffer, nil)
		vk.DestroyImageView(device, image.view, nil)
		vk.DestroySemaphore(device, image.ready, nil)
	}
	delete(r.images, runtime.heap_allocator())
	r.images = nil
	vk.DestroySwapchainKHR(device, r.swapchain, nil)
	r.swapchain = 0
}

@(private="file")
release_pipeline :: proc(r: ^Renderer) {
	device := r.vulkan.device
	for _, pipeline in r.shader_pipelines {
		vk.DestroyPipeline(device, pipeline, nil)
	}
	delete(r.shader_pipelines)
	r.shader_pipelines = nil
	vk.DestroyPipeline(device, r.pipeline, nil)
	vk.DestroyRenderPass(device, r.render_pass, nil)
	r.pipeline = 0
	r.render_pass = 0
}

@(private="file")
surface_format :: proc(v: ^Vulkan, surface: vk.SurfaceKHR) -> (vk.SurfaceFormatKHR, bool) {
	count: u32
	if !vulkan_ok(vk.GetPhysicalDeviceSurfaceFormatsKHR(v.physical_device, surface, &count, nil), "count surface formats") || count == 0 {
		return {}, false
	}
	formats := make([]vk.SurfaceFormatKHR, int(count), context.temp_allocator)
	if !vulkan_ok(vk.GetPhysicalDeviceSurfaceFormatsKHR(v.physical_device, surface, &count, raw_data(formats)), "read surface formats") {
		return {}, false
	}
	for format in formats[:count] {
		if format.format == .UNDEFINED || format.format == .B8G8R8A8_UNORM {
			return {.B8G8R8A8_UNORM, format.colorSpace}, true
		}
	}
	for format in formats[:count] {
		if format.format == .R8G8B8A8_UNORM {
			return format, true
		}
	}
	return formats[0], true
}

@(private="file")
surface_present_mode :: proc(r: ^Renderer) -> (vk.PresentModeKHR, bool) {
	device := r.vulkan.physical_device
	count: u32
	if !vulkan_ok(vk.GetPhysicalDeviceSurfacePresentModesKHR(device, r.surface, &count, nil), "count presentation modes") {
		return .FIFO, false
	}
	modes := make([]vk.PresentModeKHR, int(count), context.temp_allocator)
	if !vulkan_ok(vk.GetPhysicalDeviceSurfacePresentModesKHR(device, r.surface, &count, raw_data(modes)), "read presentation modes") {
		return .FIFO, false
	}
	for mode in modes[:count] {
		if mode == .MAILBOX {
			return mode, true
		}
	}
	return .FIFO, true
}

@(private="file")
surface_alpha :: proc(r: ^Renderer, supported: vk.CompositeAlphaFlagsKHR) -> vk.CompositeAlphaFlagsKHR {
	if r.transparent {
		if .PRE_MULTIPLIED in supported {
			return {.PRE_MULTIPLIED}
		}
		if .INHERIT in supported {
			return {.INHERIT}
		}
		return {}
	}
	if .OPAQUE in supported {
		return {.OPAQUE}
	}
	if .PRE_MULTIPLIED in supported {
		return {.PRE_MULTIPLIED}
	}
	if .POST_MULTIPLIED in supported {
		return {.POST_MULTIPLIED}
	}
	return {.INHERIT}
}

@(private="file")
create_swapchain :: proc(r: ^Renderer, pixel_size: [2]i32) -> vk.Result {
	v := r.vulkan
	capabilities: vk.SurfaceCapabilitiesKHR
	result := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(v.physical_device, r.surface, &capabilities)
	if result != .SUCCESS {
		return result
	}
	extent := capabilities.currentExtent
	if extent.width == max(u32) {
		extent = {
			clamp(u32(pixel_size.x), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
			clamp(u32(pixel_size.y), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
		}
	}
	if extent.width == 0 || extent.height == 0 {
		return .NOT_READY
	}
	format, format_ok := surface_format(v, r.surface)
	mode, mode_ok := surface_present_mode(r)
	if !format_ok || !mode_ok {
		return .ERROR_INITIALIZATION_FAILED
	}
	count := max(u32(3), capabilities.minImageCount)
	if capabilities.maxImageCount > 0 {
		count = min(count, capabilities.maxImageCount)
	}
	if r.swapchain != 0 {
		if result = vk.DeviceWaitIdle(v.device); result != .SUCCESS {
			return result
		}
		release_swapchain(r)
	}
	if r.render_pass == 0 || r.format != format.format {
		release_pipeline(r)
		if !create_ui_pipeline(r, format.format) {
			return .ERROR_INITIALIZATION_FAILED
		}
		r.format = format.format
	}
	alpha := surface_alpha(r, capabilities.supportedCompositeAlpha)
	if alpha == {} {
		fmt.eprintln("Vulkan surface cannot composite a transparent window")
		return .ERROR_INITIALIZATION_FAILED
	}
	info := vk.SwapchainCreateInfoKHR{
		sType = .SWAPCHAIN_CREATE_INFO_KHR, surface = r.surface, minImageCount = count,
		imageFormat = format.format, imageColorSpace = format.colorSpace, imageExtent = extent,
		imageArrayLayers = 1, imageUsage = {.COLOR_ATTACHMENT}, imageSharingMode = .EXCLUSIVE,
		preTransform = capabilities.currentTransform, compositeAlpha = alpha,
		presentMode = mode, clipped = true,
	}
	if result = vk.CreateSwapchainKHR(v.device, &info, nil, &r.swapchain); result != .SUCCESS {
		return result
	}
	r.extent = extent
	r.present_mode = mode
	if !create_swapchain_images(r, format.format) {
		return .ERROR_INITIALIZATION_FAILED
	}
	r.requested_size = pixel_size
	r.recreate = false
	return .SUCCESS
}

@(private="file")
create_swapchain_images :: proc(r: ^Renderer, format: vk.Format) -> bool {
	device := r.vulkan.device
	count: u32
	if !vulkan_ok(vk.GetSwapchainImagesKHR(device, r.swapchain, &count, nil), "count swapchain images") {
		return false
	}
	handles := make([]vk.Image, int(count), context.temp_allocator)
	if !vulkan_ok(vk.GetSwapchainImagesKHR(device, r.swapchain, &count, raw_data(handles)), "read swapchain images") {
		return false
	}
	r.images = make([]Swap_Image, int(count), runtime.heap_allocator())
	semaphore := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
	present_fence := vk.FenceCreateInfo{sType = .FENCE_CREATE_INFO}
	for &image, i in r.images {
		view := vk.ImageViewCreateInfo{
			sType = .IMAGE_VIEW_CREATE_INFO, image = handles[i], viewType = .D2, format = format,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		}
		if !vulkan_ok(vk.CreateImageView(device, &view, nil, &image.view), "create swapchain image view") {
			return false
		}
		framebuffer := vk.FramebufferCreateInfo{
			sType = .FRAMEBUFFER_CREATE_INFO, renderPass = r.render_pass, attachmentCount = 1, pAttachments = &image.view,
			width = r.extent.width, height = r.extent.height, layers = 1,
		}
		if !vulkan_ok(vk.CreateFramebuffer(device, &framebuffer, nil, &image.framebuffer), "create framebuffer") ||
			!vulkan_ok(vk.CreateSemaphore(device, &semaphore, nil, &image.ready), "create presentation semaphore") {
			return false
		}
		if r.vulkan.swapchain_maintenance &&
			!vulkan_ok(vk.CreateFence(device, &present_fence, nil, &image.present_fence), "create presentation fence") {
			return false
		}
	}
	return true
}

@(private="file")
create_ui_pipeline :: proc(r: ^Renderer, format: vk.Format) -> bool {
	device := r.vulkan.device
	attachment := vk.AttachmentDescription{
		format = format, samples = {._1}, loadOp = .CLEAR, storeOp = .STORE,
		stencilLoadOp = .DONT_CARE, stencilStoreOp = .DONT_CARE, initialLayout = .UNDEFINED, finalLayout = .PRESENT_SRC_KHR,
	}
	color := vk.AttachmentReference{attachment = 0, layout = .COLOR_ATTACHMENT_OPTIMAL}
	subpass := vk.SubpassDescription{pipelineBindPoint = .GRAPHICS, colorAttachmentCount = 1, pColorAttachments = &color}
	dependency := vk.SubpassDependency{
		srcSubpass = vk.SUBPASS_EXTERNAL, dstSubpass = 0, srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
		dstStageMask = {.COLOR_ATTACHMENT_OUTPUT}, dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}
	pass := vk.RenderPassCreateInfo{
		sType = .RENDER_PASS_CREATE_INFO, attachmentCount = 1, pAttachments = &attachment,
		subpassCount = 1, pSubpasses = &subpass, dependencyCount = 1, pDependencies = &dependency,
	}
	if !vulkan_ok(vk.CreateRenderPass(device, &pass, nil, &r.render_pass), "create render pass") {
		return false
	}
	binding := vk.VertexInputBindingDescription{binding = 0, stride = size_of(Draw_Vertex), inputRate = .VERTEX}
	attributes := [?]vk.VertexInputAttributeDescription{
		{location = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Draw_Vertex, position))},
		{location = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Draw_Vertex, color))},
		{location = 2, format = .R32G32_SFLOAT, offset = u32(offset_of(Draw_Vertex, mask_position))},
		{location = 3, format = .R32G32_UINT, offset = u32(offset_of(Draw_Vertex, mask))},
	}
	inputs := vk.PipelineVertexInputStateCreateInfo{
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, vertexBindingDescriptionCount = 1, pVertexBindingDescriptions = &binding,
		vertexAttributeDescriptionCount = len(attributes), pVertexAttributeDescriptions = raw_data(attributes[:]),
	}
	// Rebuild each embedded module with glslang -V <source> -o <source>.spv.
	r.pipeline = create_graphics_pipeline(r, #load("shaders/ui.vert.spv", []u32), #load("shaders/ui.frag.spv", []u32),
		&inputs, .TRIANGLE_LIST)
	return r.pipeline != 0
}

@(private="package")
shader_pipeline :: proc(r: ^Renderer, fragment: []u32) -> vk.Pipeline {
	if len(fragment) < 5 || fragment[0] != 0x07230203 {
		return 0
	}
	key := Shader_Code{&fragment[0], len(fragment)}
	if pipeline, cached := r.shader_pipelines[key]; cached {
		return pipeline
	}
	if r.shader_pipelines == nil {
		r.shader_pipelines = make(map[Shader_Code]vk.Pipeline, runtime.heap_allocator())
	}
	inputs := vk.PipelineVertexInputStateCreateInfo{sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO}
	pipeline := create_graphics_pipeline(r, #load("shaders/shader.vert.spv", []u32), fragment, &inputs, .TRIANGLE_STRIP)
	r.shader_pipelines[key] = pipeline
	return pipeline
}

@(private="file")
create_graphics_pipeline :: proc(r: ^Renderer, vertex_code, fragment_code: []u32,
	inputs: ^vk.PipelineVertexInputStateCreateInfo, topology: vk.PrimitiveTopology,
) -> vk.Pipeline {
	device := r.vulkan.device
	vertex := load_shader(device, vertex_code)
	fragment := load_shader(device, fragment_code)
	defer vk.DestroyShaderModule(device, vertex, nil)
	defer vk.DestroyShaderModule(device, fragment, nil)
	if vertex == 0 || fragment == 0 {
		return 0
	}
	stages := [?]vk.PipelineShaderStageCreateInfo{
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = vertex, pName = "main"},
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = fragment, pName = "main"},
	}
	assembly := vk.PipelineInputAssemblyStateCreateInfo{sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO, topology = topology}
	viewport := vk.PipelineViewportStateCreateInfo{sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO, viewportCount = 1, scissorCount = 1}
	raster := vk.PipelineRasterizationStateCreateInfo{sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO, polygonMode = .FILL, lineWidth = 1}
	samples := vk.PipelineMultisampleStateCreateInfo{sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO, rasterizationSamples = {._1}}
	states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo{
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO, dynamicStateCount = len(states), pDynamicStates = raw_data(states[:]),
	}
	blend := vk.PipelineColorBlendAttachmentState{
		blendEnable = true, srcColorBlendFactor = .ONE, dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA, colorBlendOp = .ADD,
		srcAlphaBlendFactor = .ONE, dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA, alphaBlendOp = .ADD,
		colorWriteMask = {.R, .G, .B, .A},
	}
	blend_state := vk.PipelineColorBlendStateCreateInfo{sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO, attachmentCount = 1, pAttachments = &blend}
	info := vk.GraphicsPipelineCreateInfo{
		sType = .GRAPHICS_PIPELINE_CREATE_INFO, stageCount = len(stages), pStages = raw_data(stages[:]),
		pVertexInputState = inputs, pInputAssemblyState = &assembly, pViewportState = &viewport,
		pRasterizationState = &raster, pMultisampleState = &samples, pColorBlendState = &blend_state, pDynamicState = &dynamic_state,
		layout = r.vulkan.pipeline_layout, renderPass = r.render_pass, basePipelineIndex = -1,
	}
	pipeline: vk.Pipeline
	if !vulkan_ok(vk.CreateGraphicsPipelines(device, 0, 1, &info, nil, &pipeline), "create graphics pipeline") {
		vk.DestroyPipeline(device, pipeline, nil)
		return 0
	}
	return pipeline
}

@(private="file")
load_shader :: proc(device: vk.Device, words: []u32) -> vk.ShaderModule {
	info := vk.ShaderModuleCreateInfo{
		sType = .SHADER_MODULE_CREATE_INFO, codeSize = len(words) * size_of(u32), pCode = raw_data(words),
	}
	module: vk.ShaderModule
	if !vulkan_ok(vk.CreateShaderModule(device, &info, nil, &module), "load shader") {
		return 0
	}
	return module
}

@(private="package")
render_begin :: proc(r: ^Renderer, pixel_size: [2]i32, background: Color) -> bool {
	if r.failed || pixel_size.x <= 0 || pixel_size.y <= 0 {
		return false
	}
	if r.swapchain == 0 || r.recreate || r.requested_size != pixel_size {
		result := create_swapchain(r, pixel_size)
		#partial switch result {
		case .SUCCESS:
		case .NOT_READY, .ERROR_OUT_OF_DATE_KHR:
			return false
		case:
			vulkan_ok(result, "create swapchain")
			r.failed = true
			return false
		}
	}
	clear(&r.vertices)
	clear(&r.indices)
	clear(&r.masks)
	clear(&r.batches)
	r.clip = {0, 0, i32(r.extent.width), i32(r.extent.height)}
	r.recording = true
	render_fill_rect(r, {0, 0, f32(r.extent.width), f32(r.extent.height)}, background)
	return true
}

@(private="package")
render_present :: proc(r: ^Renderer, clip: Maybe(Window_Circle)) -> bool {
	if !r.recording {
		return false
	}
	r.recording = false
	v := r.vulkan
	frame := &r.frames[r.frame_index]
	if !vulkan_ok(vk.WaitForFences(v.device, 1, &frame.completed, true, max(u64)), "wait for frame fence") ||
		!upload_frame(r, frame) {
		r.failed = true
		return false
	}
	image_index: u32
	result := vk.AcquireNextImageKHR(v.device, r.swapchain, 1_000_000, frame.acquired, 0, &image_index)
	#partial switch result {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR:
		r.recreate = true
	case .ERROR_OUT_OF_DATE_KHR:
		r.recreate = true
		return false
	case .NOT_READY, .TIMEOUT:
		return false
	case:
		vulkan_ok(result, "acquire a swapchain image")
		r.failed = true
		return false
	}
	image := &r.images[image_index]
	if image.present_pending {
		if !vulkan_ok(vk.WaitForFences(v.device, 1, &image.present_fence, true, max(u64)), "wait for presentation fence") ||
			!vulkan_ok(vk.ResetFences(v.device, 1, &image.present_fence), "reset presentation fence") {
			r.failed = true
			return false
		}
		image.present_pending = false
	}
	if !record_frame(r, frame, image.framebuffer, clip) ||
		!vulkan_ok(vk.ResetFences(v.device, 1, &frame.completed), "reset frame fence") {
		r.failed = true
		return false
	}
	stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	submit := vk.SubmitInfo{
		sType = .SUBMIT_INFO, waitSemaphoreCount = 1, pWaitSemaphores = &frame.acquired, pWaitDstStageMask = &stage,
		commandBufferCount = 1, pCommandBuffers = &frame.command, signalSemaphoreCount = 1, pSignalSemaphores = &image.ready,
	}
	if !vulkan_ok(vk.QueueSubmit(v.queue, 1, &submit, frame.completed), "submit frame") {
		r.failed = true
		return false
	}
	r.frame_index = (r.frame_index + 1) % FRAMES_IN_FLIGHT
	present := vk.PresentInfoKHR{
		sType = .PRESENT_INFO_KHR, waitSemaphoreCount = 1, pWaitSemaphores = &image.ready,
		swapchainCount = 1, pSwapchains = &r.swapchain, pImageIndices = &image_index,
	}
	fence_info := vk.SwapchainPresentFenceInfoKHR{
		sType = .SWAPCHAIN_PRESENT_FENCE_INFO_KHR, swapchainCount = 1, pFences = &image.present_fence,
	}
	if v.swapchain_maintenance {
		present.pNext = &fence_info
	}
	result = vk.QueuePresentKHR(v.queue, &present)
	// Presentation errors issued by the compositor still enqueue their synchronization.
	image.present_pending = v.swapchain_maintenance && (result == .SUCCESS || result == .SUBOPTIMAL_KHR ||
		result == .ERROR_OUT_OF_DATE_KHR || result == .ERROR_SURFACE_LOST_KHR)
	#partial switch result {
	case .SUCCESS:
	case .SUBOPTIMAL_KHR, .ERROR_OUT_OF_DATE_KHR:
		r.recreate = true
	case:
		vulkan_ok(result, "present frame")
		r.failed = true
	}
	return result == .SUCCESS || result == .SUBOPTIMAL_KHR
}

@(private="file")
upload_frame :: proc(r: ^Renderer, frame: ^Render_Frame) -> bool {
	if len(r.indices) == 0 {
		return true
	}
	v := r.vulkan
	vertex_bytes := len(r.vertices) * size_of(Draw_Vertex)
	geometry_bytes := vertex_bytes + len(r.indices) * size_of(u32)
	if !ensure_buffer(v, &frame.geometry, geometry_bytes, {.VERTEX_BUFFER, .INDEX_BUFFER}) {
		return false
	}
	vertices := (cast([^]Draw_Vertex) frame.geometry.data)[:len(r.vertices)]
	indices := (cast([^]u32) (uintptr(frame.geometry.data) + uintptr(vertex_bytes)))[:len(r.indices)]
	copy(vertices, r.vertices[:])
	copy(indices, r.indices[:])
	mask_bytes := max(4, (len(r.masks) + 3) &~ 3)
	if mask_bytes > v.mask_limit {
		fmt.eprintln("The frame's text masks exceed the Vulkan storage buffer limit.")
		return false
	}
	if frame.masks.size < mask_bytes {
		if !ensure_buffer(v, &frame.masks, mask_bytes, {.STORAGE_BUFFER}, v.mask_limit) {
			return false
		}
		buffer := vk.DescriptorBufferInfo{buffer = frame.masks.handle, range = vk.DeviceSize(frame.masks.size)}
		write := vk.WriteDescriptorSet{
			sType = .WRITE_DESCRIPTOR_SET, dstSet = frame.descriptor, descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER, pBufferInfo = &buffer,
		}
		vk.UpdateDescriptorSets(v.device, 1, &write, 0, nil)
	}
	masks := (cast([^]u8) frame.masks.data)[:mask_bytes]
	copy(masks, r.masks[:])
	return true
}

@(private="file")
ensure_buffer :: proc(v: ^Vulkan, buffer: ^Mapped_Buffer, bytes: int, usage: vk.BufferUsageFlags, limit: int = max(int)) -> bool {
	if buffer.size >= bytes {
		return true
	}
	size := min(limit, max(bytes, max(16 * 1024, buffer.size * 2)))
	release_buffer(v.device, buffer)
	info := vk.BufferCreateInfo{
		sType = .BUFFER_CREATE_INFO, size = vk.DeviceSize(size), usage = usage, sharingMode = .EXCLUSIVE,
	}
	if !vulkan_ok(vk.CreateBuffer(v.device, &info, nil, &buffer.handle), "create upload buffer") {
		return false
	}
	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(v.device, buffer.handle, &requirements)
	type_index := -1
	for memory_type, i in v.memory.memoryTypes[:v.memory.memoryTypeCount] {
		if (requirements.memoryTypeBits & (1 << u32(i))) != 0 &&
			.HOST_VISIBLE in memory_type.propertyFlags && .HOST_COHERENT in memory_type.propertyFlags {
			type_index = i
			break
		}
	}
	if type_index < 0 {
		fmt.eprintln("Vulkan did not find coherent host-visible upload memory.")
		return false
	}
	allocate := vk.MemoryAllocateInfo{
		sType = .MEMORY_ALLOCATE_INFO, allocationSize = requirements.size, memoryTypeIndex = u32(type_index),
	}
	if !vulkan_ok(vk.AllocateMemory(v.device, &allocate, nil, &buffer.memory), "allocate upload memory") ||
		!vulkan_ok(vk.BindBufferMemory(v.device, buffer.handle, buffer.memory, 0), "bind upload memory") ||
		!vulkan_ok(vk.MapMemory(v.device, buffer.memory, 0, vk.DeviceSize(size), {}, &buffer.data), "map upload memory") {
		return false
	}
	buffer.size = size
	return true
}

@(private="file")
release_buffer :: proc(device: vk.Device, buffer: ^Mapped_Buffer) {
	if buffer.data != nil {
		vk.UnmapMemory(device, buffer.memory)
	}
	vk.DestroyBuffer(device, buffer.handle, nil)
	vk.FreeMemory(device, buffer.memory, nil)
	buffer^ = {}
}

@(private="file")
record_frame :: proc(r: ^Renderer, frame: ^Render_Frame, framebuffer: vk.Framebuffer, clip: Maybe(Window_Circle)) -> bool {
	command := frame.command
	begin := vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO, flags = {.ONE_TIME_SUBMIT}}
	if !vulkan_ok(vk.ResetCommandBuffer(command, {}), "reset command buffer") ||
		!vulkan_ok(vk.BeginCommandBuffer(command, &begin), "begin command buffer") {
		return false
	}
	clear_value := vk.ClearValue{color = {float32 = {0, 0, 0, 0}}}
	pass := vk.RenderPassBeginInfo{
		sType = .RENDER_PASS_BEGIN_INFO, renderPass = r.render_pass, framebuffer = framebuffer,
		renderArea = {extent = r.extent}, clearValueCount = 1, pClearValues = &clear_value,
	}
	vk.CmdBeginRenderPass(command, &pass, .INLINE)
	if len(r.batches) > 0 {
		w, h := f32(r.extent.width), f32(r.extent.height)
		viewport := vk.Viewport{width = w, height = h, maxDepth = 1}
		params := Frame_Constants{scale = {2 / w, 2 / h}}
		if circle, clipped := clip.?; clipped {
			params.circle_center = circle.center
			params.circle_radius_squared = circle.radius * circle.radius
			params.clip_enabled = 1
		}
		layout := r.vulkan.pipeline_layout
		vk.CmdSetViewport(command, 0, 1, &viewport)
		vk.CmdPushConstants(command, layout, {.VERTEX, .FRAGMENT}, 0, size_of(params), &params)
		if len(r.indices) > 0 {
			vk.CmdBindDescriptorSets(command, .GRAPHICS, layout, 0, 1, &frame.descriptor, 0, nil)
			start: vk.DeviceSize
			vk.CmdBindVertexBuffers(command, 0, 1, &frame.geometry.handle, &start)
			vk.CmdBindIndexBuffer(command, frame.geometry.handle, vk.DeviceSize(len(r.vertices) * size_of(Draw_Vertex)), .UINT32)
		}
		bound: vk.Pipeline
		for &batch in r.batches {
			pipeline := batch.shader.pipeline != 0 ? batch.shader.pipeline : r.pipeline
			if pipeline != bound {
				vk.CmdBindPipeline(command, .GRAPHICS, pipeline)
				bound = pipeline
			}
			rect := batch.clip
			scissor := vk.Rect2D{offset = {rect.x, rect.y}, extent = {u32(rect.w), u32(rect.h)}}
			vk.CmdSetScissor(command, 0, 1, &scissor)
			if batch.shader.pipeline != 0 {
				vk.CmdPushConstants(command, layout, {.VERTEX, .FRAGMENT}, u32(offset_of(Frame_Constants, shader)),
					size_of(Shader_Constants), &batch.shader.constants)
				vk.CmdDraw(command, 4, 1, 0, 0)
			} else {
				vk.CmdDrawIndexed(command, batch.count, 1, batch.first, 0, 0)
			}
		}
	}
	vk.CmdEndRenderPass(command)
	return vulkan_ok(vk.EndCommandBuffer(command), "end command buffer")
}
