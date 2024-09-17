package device
import vk "vendor:vulkan"
import "vendor:glfw"
import sdl "vendor:sdl2"
import "core:fmt"
import "core:c/libc"
import "core:slice"

VALIDATION_LAYERS :: [1]cstring{"VK_LAYER_KHRONOS_validation"}
VALIDATION_FEATURES :: [1]vk.ValidationFeatureEnableEXT{
    vk.ValidationFeatureEnableEXT.DEBUG_PRINTF
}

DeviceContext :: struct
{
    enable_validation_layers: bool,
    width:                    i32,
    height:                   i32,
    window:                   ^sdl.Window,
    instance:                 vk.Instance,
    debug_messager:           vk.DebugUtilsMessengerEXT,
    surface:                  vk.SurfaceKHR,
    physical_device:          vk.PhysicalDevice,
    physical_device_max_useable_sample_count : vk.SampleCountFlag,
    best_depth_stencil_format : vk.Format,
    device:                   vk.Device,
    graphics_queue:           vk.Queue,
    present_queue:            vk.Queue,
    command_buffer:           CommandBufferContext,
    swap_chain:               SwapChainContext
}

make_device :: proc(
    enable_validation_layers : bool,
    feature_set : FeatureSet,
    name : cstring,
    width: i32, height: i32
) -> DeviceContext
{
    device_context := DeviceContext{}
    device_context.enable_validation_layers = enable_validation_layers
    device_context.width = width
    device_context.height = height
    setup_sld(&device_context, name, width, height)
    setup_instance_and_setup_debug_layers(&device_context, name)
    setup_surface(&device_context)
    setup_physical_device(&device_context, feature_set.required_physical_device_extentions)
    last_in_feature_chain := feature_set.feature_chain[len(feature_set.feature_chain) - 1]
    setup_logical_device_and_queues(&device_context, feature_set.required_physical_device_extentions, last_in_feature_chain)
    device_context.command_buffer = make_command_pool_and_buffer(&device_context)
    device_context.swap_chain = make_swap_chain(&device_context)

    delete_feature_set(feature_set)
    return device_context
}

delete_device :: proc(device_context : DeviceContext)
{
    device_copy := device_context
    delete_swap_chain(&device_copy, device_context.swap_chain)
    delete_command_pool_and_buffer(&device_copy, device_context.command_buffer)
    vk.DestroyDevice(
        device_context.device,
        nil
    )
    vk.DestroySurfaceKHR(
        device_context.instance,
        device_context.surface,
        nil
    )
    vk.DestroyDebugUtilsMessengerEXT(
        device_context.instance,
        device_context.debug_messager,
        nil
    )
    vk.DestroyInstance(
        device_context.instance,
        nil
    )
    sdl.DestroyWindow(device_context.window)
}

setup_sld :: proc(device_context : ^DeviceContext, name : cstring, width: i32, height: i32)
{
    sdl.Init({sdl.InitFlag.VIDEO})
    sdl.Vulkan_LoadLibrary(nil)
    device_context.window = sdl.CreateWindow(
        name,
        sdl.WINDOWPOS_UNDEFINED, sdl.WINDOWPOS_UNDEFINED,
        width, height,
        {sdl.WindowFlag.SHOWN, sdl.WindowFlag.VULKAN}
    )
}

setup_instance_and_setup_debug_layers :: proc(device_context : ^DeviceContext, name : cstring)
{
    // vulkan setup
    vk.load_proc_addresses_global(sdl.Vulkan_GetVkGetInstanceProcAddr())

    // app info
    app_info := vk.ApplicationInfo{}
    app_info.sType = vk.StructureType.APPLICATION_INFO
    app_info.pApplicationName = name
    app_info.applicationVersion = vk.MAKE_VERSION(1, 3, 0)
    app_info.pEngineName = "Acorn"
    app_info.engineVersion = vk.MAKE_VERSION(1, 3, 0)
    app_info.apiVersion = vk.MAKE_VERSION(1, 3, 0)

    // debug messenger info
    debug_messenger_create_info := vk.DebugUtilsMessengerCreateInfoEXT{}
    debug_messenger_create_info.sType =
        vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
    debug_messenger_create_info.messageSeverity = {
        vk.DebugUtilsMessageSeverityFlagsEXT.ERROR,
        vk.DebugUtilsMessageSeverityFlagEXT.WARNING,
        vk.DebugUtilsMessageSeverityFlagEXT.VERBOSE,
        vk.DebugUtilsMessageSeverityFlagEXT.INFO,
    }
    debug_messenger_create_info.messageType = {
        vk.DebugUtilsMessageTypeFlagEXT.GENERAL,
        vk.DebugUtilsMessageTypeFlagEXT.VALIDATION,
        vk.DebugUtilsMessageTypeFlagEXT.PERFORMANCE,
        vk.DebugUtilsMessageTypeFlagEXT.DEVICE_ADDRESS_BINDING,
    }
    debug_messenger_create_info.pfnUserCallback = debug_callback
    debug_messenger_create_info.pUserData = nil

    // adds the ability to printf
    validation_features := vk.ValidationFeaturesEXT{}
    validation_features.sType = vk.StructureType.VALIDATION_FEATURES_EXT
    validation_features_copy := VALIDATION_FEATURES
    validation_features.enabledValidationFeatureCount = len(validation_features_copy)
    validation_features.pEnabledValidationFeatures = raw_data(&validation_features_copy)
    validation_features.pNext = &debug_messenger_create_info

    // create info
    create_info := vk.InstanceCreateInfo{}
    create_info.sType = vk.StructureType.INSTANCE_CREATE_INFO
    create_info.pApplicationInfo = &app_info

    sdl_extensions := get_required_instance_extensions(device_context) // extentrions required for debugging and by sdl
    defer delete(sdl_extensions)
    create_info.enabledExtensionCount = u32(len(sdl_extensions))
    create_info.ppEnabledExtensionNames = raw_data(sdl_extensions)

    required_validation_layers := VALIDATION_LAYERS
    if device_context.enable_validation_layers &&
       !are_validation_layers_supported(required_validation_layers[:]) {
        panic("a validation layer is not supported")
    }
    if device_context.enable_validation_layers {
        create_info.enabledLayerCount = len(required_validation_layers)
        create_info.ppEnabledLayerNames = raw_data(&required_validation_layers)

        create_info.pNext = &validation_features
    } else {
        create_info.enabledLayerCount = 0
    }

    if vk.CreateInstance(&create_info, nil, &device_context.instance) !=
       vk.Result.SUCCESS {
        panic("failed to craete instance")
    }

    vk.load_proc_addresses_instance(device_context.instance)

    // add debug callback
    if device_context.enable_validation_layers {
        // this might not work cause Im supposet to look it up or somthing
        if vk.CreateDebugUtilsMessengerEXT(
               device_context.instance,
               &debug_messenger_create_info,
               nil,
               &device_context.debug_messager,
           ) !=
           vk.Result.SUCCESS {
            fmt.println("failed to craete debug_messager")
            return
        }
    }
}

debug_callback :: proc "system" (
    messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
    messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
    pUserData: rawptr,
) -> b32
{
    if pCallbackData.pMessage != nil
    {
        if .WARNING in messageSeverity
        {
            libc.printf("\e[33m", pCallbackData.pMessage)
        }
        else if .ERROR in messageSeverity
        {
            libc.printf("\e[31m", pCallbackData.pMessage)
        }
        libc.printf("\n%s\e[0m\n\n", pCallbackData.pMessage)
    }
    return false
}

get_required_instance_extensions :: proc(device_context : ^DeviceContext) -> [dynamic]cstring
{
    extention_cout : u32 = 0
    sdl.Vulkan_GetInstanceExtensions(device_context.window, &extention_cout, nil)
    sdl_extensions := make([dynamic]cstring, extention_cout)
    sdl.Vulkan_GetInstanceExtensions(device_context.window, &extention_cout, raw_data(sdl_extensions))

    if device_context.enable_validation_layers {
        append(&sdl_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
    }

    return sdl_extensions
}

are_validation_layers_supported :: proc(required_layers: []cstring) -> bool
{
    layer_count: u32
    vk.EnumerateInstanceLayerProperties(&layer_count, nil)

    avail_layers := make([]vk.LayerProperties, layer_count)
    defer delete(avail_layers)
    vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(avail_layers))

    for validation_layer in required_layers {

        layer_found := false

        for &layer_property in avail_layers
        {
            buff: [256]u8 = layer_property.layerName
            if validation_layer ==
               cast(cstring)rawptr(&layer_property.layerName) {
                layer_found = true
                break
            }
        }

        if !layer_found {
            return false
        }
    }

    return true
}

setup_surface :: proc(device_context : ^DeviceContext)
{
    if !sdl.Vulkan_CreateSurface(
            device_context.window,
            device_context.instance,
            &device_context.surface,
    )
    {
        panic("failed to create surface")
    }
}

setup_physical_device :: proc(
    device_context : ^DeviceContext,
    required_physical_device_extentions : []cstring
)
{
    err: PhysicalDeviceError
    device_context.physical_device, err = select_physical_device(
        device_context.instance,
        device_context.surface,
        required_physical_device_extentions
    )

    if err != .None {
        panic("no gpu that is good enough")
    }

    device_context.physical_device_max_useable_sample_count = get_max_useable_sample_count(device_context.physical_device)
    device_context.best_depth_stencil_format = get_best_supported_depth_format(device_context.physical_device)
}

PhysicalDeviceError :: enum {
    None,
    NoGPUSSupportVulkan,
    NoGPUSSupportRequiredFeatures,
}

get_max_useable_sample_count :: proc(physical_device : vk.PhysicalDevice) -> vk.SampleCountFlag
{
    device_properties := vk.PhysicalDeviceProperties{}
    vk.GetPhysicalDeviceProperties(physical_device, &device_properties)
    counts := device_properties.limits.framebufferColorSampleCounts
    if (vk.SampleCountFlag._64 in counts) { return vk.SampleCountFlag._64 }
    if (vk.SampleCountFlag._32 in counts) { return vk.SampleCountFlag._32 }
    if (vk.SampleCountFlag._16 in counts) { return vk.SampleCountFlag._16 }
    if (vk.SampleCountFlag._8 in counts) { return vk.SampleCountFlag._8 }
    if (vk.SampleCountFlag._4 in counts) { return vk.SampleCountFlag._4 }
    if (vk.SampleCountFlag._2 in counts) { return vk.SampleCountFlag._2 }
    return vk.SampleCountFlag._1
}

get_best_supported_depth_format :: proc(physical_device : vk.PhysicalDevice) -> vk.Format
{
    valid_formats := []vk.Format{
        vk.Format.D32_SFLOAT,
        vk.Format.D32_SFLOAT_S8_UINT,
        vk.Format.D24_UNORM_S8_UINT
    }
    for format in valid_formats
    {
        format_properties := vk.FormatProperties{}
        vk.GetPhysicalDeviceFormatProperties(physical_device, format, &format_properties)
        if vk.FormatFeatureFlag.DEPTH_STENCIL_ATTACHMENT in format_properties.optimalTilingFeatures
        {
            return format
        }
    }
    panic("cannot find a valid depth format")
}

format_has_stencil_component :: proc(format : vk.Format) -> bool
{
    return format == vk.Format.D32_SFLOAT_S8_UINT || format == vk.Format.D24_UNORM_S8_UINT
}

get_sampler_max_anisotropy :: proc(device_context : ^DeviceContext) -> f32
{
    properties := vk.PhysicalDeviceProperties{}
    vk.GetPhysicalDeviceProperties(device_context.physical_device, &properties)
    return properties.limits.maxSamplerAnisotropy
}

select_physical_device :: proc(
    instance: vk.Instance,
    surface: vk.SurfaceKHR,
    required_physical_device_extentions : []cstring
) -> (
    vk.PhysicalDevice,
    PhysicalDeviceError,
) {
    device_count: u32 = 0
    vk.EnumeratePhysicalDevices(instance, &device_count, nil)
    if (device_count == 0) {
        panic("no gpus that support vulkan")
    }
    physical_devices := make([]vk.PhysicalDevice, device_count)
    defer delete(physical_devices)
    vk.EnumeratePhysicalDevices(
        instance,
        &device_count,
        raw_data(physical_devices),
    )


    selected_physical_device: vk.PhysicalDevice
    best_device_score := -1
    for device in physical_devices {
        device_score := 0

        device_properties := vk.PhysicalDeviceProperties{}
        device_features := vk.PhysicalDeviceFeatures{}

        vk.GetPhysicalDeviceProperties(device, &device_properties)
        vk.GetPhysicalDeviceFeatures(device, &device_features)

        if device_properties.deviceType == vk.PhysicalDeviceType.DISCRETE_GPU {
            device_score += 1000
        }
        if !device_features.geometryShader {
            continue // this feature is required
        }
        if !device_features.samplerAnisotropy {
            continue // this feature is required
        }
        if !device_features.shaderInt16 {
            continue // this feature is required
        }

        // check extentions
        extention_count: u32 = 0
        vk.EnumerateDeviceExtensionProperties(
            device,
            nil,
            &extention_count,
            nil,
        )

        extention_properties := make([]vk.ExtensionProperties, extention_count)
        defer delete(extention_properties)
        vk.EnumerateDeviceExtensionProperties(
            device,
            nil,
            &extention_count,
            raw_data(extention_properties),
        )

        has_all_required_extentions := true
        for j in 0 ..< len(required_physical_device_extentions) {
            has_extention := false
            for i in 0 ..< extention_count {
                if required_physical_device_extentions[j] ==
                   cast(cstring)rawptr(
                           &extention_properties[i].extensionName,
                       ) {
                    has_extention = true
                }
            }
            if !has_extention {
                has_all_required_extentions = false
            }
        }

        if !has_all_required_extentions {
            continue // the extentions are required so we cannot
        }

        // check what queues it has
        queue_info := get_queue_info(device, surface)

        if !queue_info.has_all_queues {
            continue // the queses are required so we cannot
        }

        // check we have the swap chains we want
        swap_chain_support_info := get_swap_chain_support_info(device, surface)

        if len(swap_chain_support_info.formats) == 0 ||
           len(swap_chain_support_info.present_modes) == 0 {
            continue // swap chains are inadiquate
        }

        if device_score > best_device_score {
            best_device_score = device_score
            selected_physical_device = device
        }
    }
    if best_device_score >= 0 {
        return selected_physical_device, .None
    } else {
        return nil, .NoGPUSSupportRequiredFeatures
    }
}

QueueInfo :: struct {
    graphics_family_index: u32,
    present_family_index:  u32,
    has_graphics_queue:    bool,
    has_present_queue:     bool,
    has_all_queues:        bool,
}

get_queue_info :: proc(
    selected_physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) -> QueueInfo {
    queue_family_count: u32 = 0
    vk.GetPhysicalDeviceQueueFamilyProperties(
        selected_physical_device,
        &queue_family_count,
        nil,
    )
    queue_familys := make([]vk.QueueFamilyProperties, queue_family_count)
    defer delete(queue_familys)
    vk.GetPhysicalDeviceQueueFamilyProperties(
        selected_physical_device,
        &queue_family_count,
        raw_data(queue_familys),
    )

    ans := QueueInfo{}
    i: u32 = 0
    for queue_family in queue_familys {
        if vk.QueueFlags.GRAPHICS in queue_family.queueFlags {
            ans.graphics_family_index = i
            ans.has_graphics_queue = true
        }

        present_support: b32
        vk.GetPhysicalDeviceSurfaceSupportKHR(
            selected_physical_device,
            i,
            surface,
            &present_support,
        )
        if present_support {
            ans.present_family_index = i
            ans.has_present_queue = true
        }

        i += 1
    }

    ans.has_all_queues = ans.has_graphics_queue || ans.has_present_queue

    return ans
}

setup_logical_device_and_queues :: proc(
    device_context : ^DeviceContext,
    required_physical_device_extentions : []cstring,
    feature_chain : rawptr
)
{
    // find queue family
    queue_info := get_queue_info(
        device_context.physical_device,
        device_context.surface,
    )

    if !queue_info.has_all_queues {
        panic("no gpu has_all_queues")
    }

    // create queues
    queues_indexes_to_create := make([dynamic]u32)
    append(&queues_indexes_to_create, queue_info.graphics_family_index)
    if queue_info.graphics_family_index != queue_info.present_family_index
    {
        append(&queues_indexes_to_create, queue_info.present_family_index)
    }

    queue_create_infos := [dynamic]vk.DeviceQueueCreateInfo{}
    queue_priority: f32 = 1
    for i in queues_indexes_to_create {
        queue_create_info := vk.DeviceQueueCreateInfo{}
        queue_create_info.sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO
        queue_create_info.queueFamilyIndex = i
        queue_create_info.queueCount = 1
        queue_create_info.pQueuePriorities = &queue_priority
        append(&queue_create_infos, queue_create_info)
    }

    device_create_info := vk.DeviceCreateInfo{}
    device_create_info.sType = vk.StructureType.DEVICE_CREATE_INFO
    device_create_info.pQueueCreateInfos = raw_data(queue_create_infos)
    device_create_info.queueCreateInfoCount = u32(len(queue_create_infos))

    device_features := vk.PhysicalDeviceFeatures{}
    device_features.samplerAnisotropy = true
    device_features.shaderInt16 = true
    device_features.shaderStorageImageReadWithoutFormat = true
    device_features.shaderStorageImageWriteWithoutFormat = true

    device_create_info.pEnabledFeatures = &device_features
    device_create_info.pNext = feature_chain

    device_create_info.enabledExtensionCount = u32(len(required_physical_device_extentions))
    device_create_info.ppEnabledExtensionNames = raw_data(required_physical_device_extentions)

    validation_layers := VALIDATION_LAYERS
    if device_context.enable_validation_layers {
        device_create_info.enabledLayerCount = len(validation_layers)
        device_create_info.ppEnabledLayerNames = raw_data(&validation_layers)
    } else {
        device_create_info.enabledLayerCount = 0
    }

    if vk.CreateDevice(
           device_context.physical_device,
           &device_create_info,
           nil,
           &device_context.device,
       ) !=
       vk.Result.SUCCESS {
        fmt.println("failed to craete a logical device")
        return
    }

    vk.GetDeviceQueue(
        device_context.device,
        queue_info.graphics_family_index,
        0,
        &device_context.graphics_queue,
    )
    vk.GetDeviceQueue(
        device_context.device,
        queue_info.present_family_index,
        0,
        &device_context.present_queue,
    )
}

begin_single_time_command :: proc(device_context : ^DeviceContext) -> vk.CommandBuffer
{
    alloc_info := vk.CommandBufferAllocateInfo{}
    alloc_info.sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO
    alloc_info.level = vk.CommandBufferLevel.PRIMARY
    alloc_info.commandPool = device_context.command_buffer.command_pool
    alloc_info.commandBufferCount = 1

    command_buffer := vk.CommandBuffer{}
    vk.AllocateCommandBuffers(device_context.device, &alloc_info, &command_buffer)

    begin_info := vk.CommandBufferBeginInfo{}
    begin_info.sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO
    begin_info.flags = {vk.CommandBufferUsageFlag.ONE_TIME_SUBMIT}
    vk.BeginCommandBuffer(command_buffer, &begin_info)

    return command_buffer
}

end_single_time_command :: proc(device_context : ^DeviceContext, command_buffer : ^vk.CommandBuffer)
{
    vk.EndCommandBuffer(command_buffer^)

    submit_info := vk.SubmitInfo{}
    submit_info.sType = vk.StructureType.SUBMIT_INFO
    submit_info.commandBufferCount = 1
    submit_info.pCommandBuffers = command_buffer

    vk.QueueSubmit(device_context.graphics_queue, 1, &submit_info, 0)
    vk.QueueWaitIdle(device_context.graphics_queue)
    vk.FreeCommandBuffers(device_context.device, device_context.command_buffer.command_pool, 1, command_buffer)
}
