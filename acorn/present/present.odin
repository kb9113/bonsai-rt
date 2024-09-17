package present
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "../resource"
import "../device"

present_image :: proc(
    device_context : ^device.DeviceContext,
    image_to_present : resource.ImageInfo,
    image_index : u32,
    wait_semaphores : []vk.Semaphore
)
{
    // transition the swap chain image to be a transphere destination
    resource.transition_image_layout_raw(
        device_context,
        device_context.swap_chain.swap_chain_images[image_index],
        device_context.swap_chain.swap_chain_surface_format_format,
        {vk.ImageAspectFlag.COLOR},
        vk.ImageLayout.UNDEFINED,
        vk.ImageLayout.TRANSFER_DST_OPTIMAL
    )

    // copy the ray out image to the swap chain image
    image_copy_info := vk.ImageBlit{}
    image_copy_info.srcOffsets = [2]vk.Offset3D{
        vk.Offset3D{0, 0, 0},
        vk.Offset3D{i32(device_context.width), i32(device_context.height), 1}
    }
    image_copy_info.dstOffsets = [2]vk.Offset3D{
        vk.Offset3D{0, 0, 0},
        vk.Offset3D{i32(device_context.width), i32(device_context.height), 1}
    }
    image_copy_info.srcSubresource = vk.ImageSubresourceLayers{}
    image_copy_info.srcSubresource.layerCount = 1
    image_copy_info.srcSubresource.aspectMask = {vk.ImageAspectFlag.COLOR}
    image_copy_info.dstSubresource = vk.ImageSubresourceLayers{}
    image_copy_info.dstSubresource.layerCount = 1
    image_copy_info.dstSubresource.aspectMask = {vk.ImageAspectFlag.COLOR}


    single_time_buffer := device.begin_single_time_command(device_context)

    vk.CmdBlitImage(
        single_time_buffer,
        image_to_present.image,
        vk.ImageLayout.GENERAL,
        device_context.swap_chain.swap_chain_images[image_index],
        vk.ImageLayout.TRANSFER_DST_OPTIMAL,
        1, &image_copy_info, vk.Filter.NEAREST
    )

    device.end_single_time_command(device_context, &single_time_buffer)

    // transtion swap chain image layout to present
    resource.transition_image_layout_raw(
        device_context,
        device_context.swap_chain.swap_chain_images[image_index],
        device_context.swap_chain.swap_chain_surface_format_format,
        {vk.ImageAspectFlag.COLOR},
        vk.ImageLayout.TRANSFER_DST_OPTIMAL,
        vk.ImageLayout.PRESENT_SRC_KHR
    )

    // present image
    present_info := vk.PresentInfoKHR{}
    present_info.sType = vk.StructureType.PRESENT_INFO_KHR

    wait_semaphores_copy := wait_semaphores
    present_info.waitSemaphoreCount = u32(len(wait_semaphores_copy))
    present_info.pWaitSemaphores = raw_data(wait_semaphores_copy)
    present_info.swapchainCount = 1
    present_info.pSwapchains = raw_data(&[1]vk.SwapchainKHR{
        device_context.swap_chain.swap_chain
    })
    image_index_copy := image_index
    present_info.pImageIndices = &image_index_copy

    queue_present_result := vk.QueuePresentKHR(device_context.present_queue, &present_info)

    vk.QueueWaitIdle(device_context.present_queue)
}
