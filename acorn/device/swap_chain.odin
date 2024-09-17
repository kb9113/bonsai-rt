package device
import vk "vendor:vulkan"
import "core:c/libc"
import "core:fmt"
import "vendor:stb/image"
import "core:math"
import sdl "vendor:sdl2"

SwapChainContext :: struct
{
    swap_chain_surface_format_format : vk.Format,
    swap_chain_extent : vk.Extent2D,
    swap_chain : vk.SwapchainKHR,
    swap_chain_images : [dynamic]vk.Image,
    swap_chain_image_views : [dynamic]vk.ImageView,
    swap_chain_image_avail_semaphore : vk.Semaphore,
}

make_swap_chain :: proc(device_context : ^DeviceContext) -> SwapChainContext
{
    ans := SwapChainContext{}
    setup_swap_chain(device_context, &ans)
    setup_image_views(device_context, &ans)
    return ans
}

delete_swap_chain :: proc(device_context : ^DeviceContext, swap_chain : SwapChainContext)
{
    delete_semaphore(device_context, swap_chain.swap_chain_image_avail_semaphore)
    for view in swap_chain.swap_chain_image_views
    {
        vk.DestroyImageView(
            device_context.device,
            view,
            nil
        )
    }
    vk.DestroySwapchainKHR(
        device_context.device,
        swap_chain.swap_chain,
        nil
    )
}

SwapChainSupportInfo :: struct {
    capabilities:  vk.SurfaceCapabilitiesKHR,
    formats:       []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
}

get_swap_chain_support_info :: proc(
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) -> SwapChainSupportInfo
{
    ans := SwapChainSupportInfo{}
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
        physical_device,
        surface,
        &ans.capabilities,
    )

    format_count: u32 = 0
    vk.GetPhysicalDeviceSurfaceFormatsKHR(
        physical_device,
        surface,
        &format_count,
        nil,
    )
    ans.formats = make([]vk.SurfaceFormatKHR, format_count)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(
        physical_device,
        surface,
        &format_count,
        raw_data(ans.formats),
    )

    present_mode_count: u32 = 0
    vk.GetPhysicalDeviceSurfacePresentModesKHR(
        physical_device,
        surface,
        &present_mode_count,
        nil,
    )
    ans.present_modes = make([]vk.PresentModeKHR, present_mode_count)
    vk.GetPhysicalDeviceSurfacePresentModesKHR(
        physical_device,
        surface,
        &present_mode_count,
        raw_data(ans.present_modes),
    )
    return ans
}

delete_swap_chain_support_info :: proc(surface_chain_support_info : SwapChainSupportInfo)
{
    delete(surface_chain_support_info.formats)
    delete(surface_chain_support_info.present_modes)
}

setup_swap_chain :: proc(device_context : ^DeviceContext, swap_chain_context : ^SwapChainContext)
{
    swap_chain_support_info := get_swap_chain_support_info(
        device_context.physical_device,
        device_context.surface,
    )
    defer delete_swap_chain_support_info(swap_chain_support_info)
    surface_format := select_swap_surface_format(
        swap_chain_support_info.formats[:],
    )
    present_mode := select_swap_preset_mode(
        swap_chain_support_info.present_modes[:],
    )
    extent := select_swap_extent(
        &swap_chain_support_info.capabilities,
        device_context.window,
    )
    swap_image_count := swap_chain_support_info.capabilities.minImageCount
    if swap_chain_support_info.capabilities.maxImageCount > 0 &&
       swap_image_count > swap_chain_support_info.capabilities.maxImageCount {
        swap_image_count = swap_chain_support_info.capabilities.maxImageCount
    }

    swap_chain_create_info := vk.SwapchainCreateInfoKHR{}
    swap_chain_create_info.sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR
    swap_chain_create_info.surface = device_context.surface
    swap_chain_create_info.minImageCount = swap_image_count
    swap_chain_create_info.imageFormat = surface_format.format
    swap_chain_context.swap_chain_surface_format_format = surface_format.format
    swap_chain_create_info.imageColorSpace = surface_format.colorSpace
    swap_chain_context.swap_chain_extent = extent
    swap_chain_create_info.imageExtent = extent
    swap_chain_create_info.imageArrayLayers = 1
    swap_chain_create_info.imageUsage = {vk.ImageUsageFlag.COLOR_ATTACHMENT, vk.ImageUsageFlag.TRANSFER_DST}

    queue_info := get_queue_info(
        device_context.physical_device,
        device_context.surface,
    )

    queues_indexes_array := [2]u32 {
        queue_info.graphics_family_index,
        queue_info.present_family_index,
    }

    if queue_info.graphics_family_index != queue_info.present_family_index {
        swap_chain_create_info.imageSharingMode = vk.SharingMode.CONCURRENT
        swap_chain_create_info.queueFamilyIndexCount = 2
        swap_chain_create_info.pQueueFamilyIndices = raw_data(
            &queues_indexes_array,
        )
    } else {
        swap_chain_create_info.imageSharingMode = vk.SharingMode.EXCLUSIVE
        swap_chain_create_info.queueFamilyIndexCount = 0
        swap_chain_create_info.pQueueFamilyIndices = nil
    }

    swap_chain_create_info.preTransform =
        swap_chain_support_info.capabilities.currentTransform
    swap_chain_create_info.compositeAlpha = {vk.CompositeAlphaFlagKHR.OPAQUE}
    swap_chain_create_info.presentMode = present_mode
    swap_chain_create_info.clipped = true
    swap_chain_create_info.oldSwapchain = vk.SwapchainKHR{}

    if vk.CreateSwapchainKHR(
           device_context.device,
           &swap_chain_create_info,
           nil,
           &swap_chain_context.swap_chain,
       ) !=
       vk.Result.SUCCESS {
        fmt.println("failed to create swap chain")
        return
    }

    swap_chain_context.swap_chain_image_avail_semaphore = create_semaphore(device_context)
}

setup_image_views :: proc(device_context : ^DeviceContext, swap_chain_context : ^SwapChainContext)
{
    swap_chain_image_count: u32 = 0
    vk.GetSwapchainImagesKHR(
        device_context.device,
        swap_chain_context.swap_chain,
        &swap_chain_image_count,
        nil,
    )
    swap_chain_context.swap_chain_images = make(
        [dynamic]vk.Image,
        swap_chain_image_count,
    )
    vk.GetSwapchainImagesKHR(
        device_context.device,
        swap_chain_context.swap_chain,
        &swap_chain_image_count,
        raw_data(swap_chain_context.swap_chain_images),
    )

    swap_chain_context.swap_chain_image_views = make(
        [dynamic]vk.ImageView,
        swap_chain_image_count,
    )

    for i in 0..<len(swap_chain_context.swap_chain_images)
    {
        swap_chain_context.swap_chain_image_views[i] = create_image_view(
            device_context,
            swap_chain_context.swap_chain_images[i],
            swap_chain_context.swap_chain_surface_format_format,
            {vk.ImageAspectFlag.COLOR}
        )
    }
}

create_image_view :: proc(device_context : ^DeviceContext, image : vk.Image, format : vk.Format, aspect_flags : vk.ImageAspectFlags) -> vk.ImageView
{
    view_info := vk.ImageViewCreateInfo{}
    view_info.sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO
    view_info.image = image
    view_info.viewType = vk.ImageViewType.D2
    view_info.format = format
    view_info.subresourceRange.aspectMask = aspect_flags
    view_info.subresourceRange.baseMipLevel = 0
    view_info.subresourceRange.levelCount = 1
    view_info.subresourceRange.baseArrayLayer = 0
    view_info.subresourceRange.layerCount = 1

    ans := vk.ImageView{}
    if vk.CreateImageView(device_context.device, &view_info, nil, &ans) != vk.Result.SUCCESS
    {
        fmt.println("oh no could not craete image view")
        panic("oh no")
    }

    return ans
}

select_swap_extent :: proc(
    capabilities: ^vk.SurfaceCapabilitiesKHR,
    window: ^sdl.Window,
) -> vk.Extent2D {
    if capabilities.currentExtent.width != libc.UINT32_MAX {
        return capabilities.currentExtent
    } else {
        width, height : i32
        sdl.GetWindowSize(window, &width, &height)
        ans := vk.Extent2D{}
        ans.width = math.clamp(
            u32(width),
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width,
        )
        ans.height = math.clamp(
            u32(height),
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height,
        )
        return ans
    }
}

select_swap_surface_format :: proc(
    avail_formats: []vk.SurfaceFormatKHR,
) -> vk.SurfaceFormatKHR {
    for format in avail_formats {
        if format.format == vk.Format.B8G8R8A8_SRGB &&
           format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
            return format
        }
    }
    fmt.println("Could not find a good format using a random one")
    return avail_formats[0]
}

select_swap_preset_mode :: proc(
    preset_modes: []vk.PresentModeKHR,
) -> vk.PresentModeKHR {

    for preset_mode in preset_modes {
        if preset_mode == vk.PresentModeKHR.MAILBOX {
            return preset_mode
        }
    }
    return vk.PresentModeKHR.FIFO
}

get_next_swap_chain_image :: proc(device_context : ^DeviceContext) -> (u32, vk.Semaphore)
{
    image_index := u32(0)
    assert(
        vk.AcquireNextImageKHR(
            device_context.device,
            device_context.swap_chain.swap_chain,
            libc.UINT64_MAX,
            device_context.swap_chain.swap_chain_image_avail_semaphore,
            0,
            &image_index
        ) == vk.Result.SUCCESS
    );
    return image_index, device_context.swap_chain.swap_chain_image_avail_semaphore
}

present_swap_chain_image :: proc(device_context : ^DeviceContext, image_index : u32, wait_semaphore : vk.Semaphore)
{
    present_info := vk.PresentInfoKHR{}
    present_info.sType = vk.StructureType.PRESENT_INFO_KHR
    present_info.waitSemaphoreCount = 1
    present_info.pWaitSemaphores = raw_data(&[1]vk.Semaphore{
        wait_semaphore
    })
    present_info.swapchainCount = 1
    present_info.pSwapchains = raw_data(&[1]vk.SwapchainKHR{
        device_context.swap_chain.swap_chain
    })
    image_index_copy := image_index
    present_info.pImageIndices = &image_index_copy

    queue_present_result := vk.QueuePresentKHR(device_context.present_queue, &present_info)

    vk.QueueWaitIdle(device_context.present_queue)
}
