package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

ImageInfo :: struct
{
    image : vk.Image,
    image_memory : vk.DeviceMemory,
    image_view : vk.ImageView,
    format : vk.Format,
    aspect : vk.ImageAspectFlags,
    layout : vk.ImageLayout,
    usage : vk.ImageUsageFlags,
    width : vk.DeviceSize,
    height : vk.DeviceSize
}

make_image :: proc(
    device_context : ^device.DeviceContext,
    width : vk.DeviceSize, height : vk.DeviceSize,
    n_samples : vk.SampleCountFlags,
    usage : vk.ImageUsageFlags,
    format : vk.Format,
    tiling : vk.ImageTiling,
    aspect : vk.ImageAspectFlags
) -> ImageInfo
{
    ans := ImageInfo{}
    ans.width = width
    ans.height = height
    ans.format = format
    ans.aspect = aspect
    ans.layout = vk.ImageLayout.UNDEFINED
    ans.usage = usage

    image_create_info := vk.ImageCreateInfo{}
    image_create_info.sType = vk.StructureType.IMAGE_CREATE_INFO
    image_create_info.imageType = vk.ImageType.D2
    image_create_info.extent.width = u32(width)
    image_create_info.extent.height = u32(height)
    image_create_info.extent.depth = 1
    image_create_info.mipLevels = 1
    image_create_info.arrayLayers = 1
    image_create_info.format = ans.format
    image_create_info.tiling = tiling
    image_create_info.initialLayout = vk.ImageLayout.UNDEFINED
    image_create_info.usage = usage
    image_create_info.sharingMode = vk.SharingMode.EXCLUSIVE
    image_create_info.samples = n_samples
    image_create_info.flags = {}

    assert(vk.CreateImage(device_context.device, &image_create_info, nil, &ans.image) == vk.Result.SUCCESS)

    mem_requirements := vk.MemoryRequirements{}
    vk.GetImageMemoryRequirements(device_context.device, ans.image, &mem_requirements)

    allocation_info := vk.MemoryAllocateInfo{}
    allocation_info.sType = vk.StructureType.MEMORY_ALLOCATE_INFO
    allocation_info.allocationSize = mem_requirements.size
    allocation_info.memoryTypeIndex = find_memory_type(device_context, mem_requirements.memoryTypeBits, {vk.MemoryPropertyFlag.DEVICE_LOCAL})

    assert(vk.AllocateMemory(device_context.device, &allocation_info, nil, &ans.image_memory) == vk.Result.SUCCESS)

    vk.BindImageMemory(device_context.device, ans.image, ans.image_memory, 0)

    view_info := vk.ImageViewCreateInfo{}
    view_info.sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO
    view_info.image = ans.image
    view_info.viewType = vk.ImageViewType.D2
    view_info.format = ans.format
    view_info.subresourceRange.aspectMask = aspect
    view_info.subresourceRange.baseMipLevel = 0
    view_info.subresourceRange.levelCount = 1
    view_info.subresourceRange.baseArrayLayer = 0
    view_info.subresourceRange.layerCount = 1

    assert(vk.CreateImageView(device_context.device, &view_info, nil, &ans.image_view) == vk.Result.SUCCESS)

    return ans
}

transition_image_layout_raw :: proc(
    device_context : ^device.DeviceContext,
    image : vk.Image,
    format : vk.Format,
    aspect : vk.ImageAspectFlags,
    old_layout : vk.ImageLayout,
    new_layout : vk.ImageLayout
)
{
    command_buffer := device.begin_single_time_command(device_context)

    barrier := vk.ImageMemoryBarrier{}
    barrier.sType = vk.StructureType.IMAGE_MEMORY_BARRIER
    barrier.oldLayout = old_layout
    barrier.newLayout = new_layout
    barrier.srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED
    barrier.dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED

    barrier.image = image
    barrier.subresourceRange.aspectMask = aspect
    barrier.subresourceRange.baseMipLevel = 0
    barrier.subresourceRange.levelCount = 1
    barrier.subresourceRange.baseArrayLayer = 0
    barrier.subresourceRange.layerCount = 1

    source_stage : vk.PipelineStageFlags
    destination_stage : vk.PipelineStageFlags

    if old_layout == vk.ImageLayout.UNDEFINED && new_layout == vk.ImageLayout.TRANSFER_DST_OPTIMAL
    {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_WRITE}
        source_stage = {vk.PipelineStageFlag.TOP_OF_PIPE}
        destination_stage = {vk.PipelineStageFlag.TRANSFER}
    }
    else if old_layout == vk.ImageLayout.UNDEFINED && new_layout == vk.ImageLayout.GENERAL
    {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_WRITE}
        source_stage = {vk.PipelineStageFlag.TOP_OF_PIPE}
        destination_stage = {vk.PipelineStageFlag.TRANSFER}
    }
    else if old_layout == vk.ImageLayout.TRANSFER_DST_OPTIMAL && new_layout == vk.ImageLayout.SHADER_READ_ONLY_OPTIMAL
    {
        barrier.srcAccessMask = {vk.AccessFlag.TRANSFER_WRITE}
        barrier.dstAccessMask = {vk.AccessFlag.SHADER_READ}
        source_stage = {vk.PipelineStageFlag.TRANSFER}
        destination_stage = {vk.PipelineStageFlag.FRAGMENT_SHADER}
    }
    else if old_layout == vk.ImageLayout.UNDEFINED && new_layout == vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.DEPTH_STENCIL_ATTACHMENT_READ, vk.AccessFlag.DEPTH_STENCIL_ATTACHMENT_WRITE}
        source_stage = {vk.PipelineStageFlag.TOP_OF_PIPE}
        destination_stage = {vk.PipelineStageFlag.EARLY_FRAGMENT_TESTS}
    }
    else if old_layout == vk.ImageLayout.TRANSFER_DST_OPTIMAL && new_layout == vk.ImageLayout.TRANSFER_SRC_OPTIMAL
    {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_READ}
        source_stage = {vk.PipelineStageFlag.TOP_OF_PIPE}
        destination_stage = {vk.PipelineStageFlag.TRANSFER}
    }
    else if old_layout == vk.ImageLayout.TRANSFER_DST_OPTIMAL && new_layout == vk.ImageLayout.PRESENT_SRC_KHR
    {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_READ}
        source_stage = {vk.PipelineStageFlag.TOP_OF_PIPE}
        destination_stage = {vk.PipelineStageFlag.TRANSFER}
    }
    else if old_layout == vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL && new_layout == vk.ImageLayout.GENERAL
    {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_READ}
        source_stage = {vk.PipelineStageFlag.TOP_OF_PIPE}
        destination_stage = {vk.PipelineStageFlag.TRANSFER}
    }
    else if old_layout == vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL && new_layout == vk.ImageLayout.GENERAL
    {
        barrier.srcAccessMask = {}
        barrier.dstAccessMask = {vk.AccessFlag.TRANSFER_READ}
        source_stage = {vk.PipelineStageFlag.TOP_OF_PIPE}
        destination_stage = {vk.PipelineStageFlag.TRANSFER}
    }
    else
    {
        fmt.println("unssuported source or destination" , old_layout, "->", new_layout)
        assert(false)
    }

    vk.CmdPipelineBarrier(
        command_buffer,
        source_stage, destination_stage,
        {},
        0, nil,
        0, nil,
        1, &barrier
    )

    device.end_single_time_command(device_context, &command_buffer)
}

transition_image_layout :: proc(
    device_context : ^device.DeviceContext,
    image : ^ImageInfo,
    new_layout : vk.ImageLayout
)
{
    transition_image_layout_raw(
        device_context,
        image.image,
        image.format,
        image.aspect,
        image.layout,
        new_layout
    )

    image.layout = new_layout
}

copy_host_cohearent_buffer_to_image :: proc(
    device_context : ^device.DeviceContext,
    host_cohearent_buffer : HostCoherhentBufferInfo($T),
    image : ImageInfo
)
{
    assert(image.layout == vk.ImageLayout.TRANSFER_DST_OPTIMAL)
    assert(image.width * image.height == host_cohearent_buffer.buffer_size / size_of(T))
    switch typeid_of(T)
    {
        case [4]u8: assert(image.format == vk.Format.R8G8B8A8_UNORM ||
            image.format == vk.Format.R8G8B8A8_SRGB
        )
        case: panic("image format not supported for coppy")
    }
    copy_buffer_to_image(
        device_context,
        host_cohearent_buffer.buffer,
        image.image,
        u32(image.width),
        u32(image.height)
    )
}

copy_image_to_new_host_coherent_buffer :: proc(
    device_context : ^device.DeviceContext,
    $T : typeid,
    image : ImageInfo
) -> HostCoherhentBufferInfo(T)
{
    switch typeid_of(T)
    {
        case [4]u8: assert(image.format == vk.Format.R8G8B8A8_UNORM ||
            image.format == vk.Format.R8G8B8A8_SRGB
        )
        case [4]u16: assert(image.format == vk.Format.R16G16B16A16_UNORM)
        case [4]f32: assert(image.format == vk.Format.R32G32B32A32_SFLOAT)
        case: panic("image format not supported for coppy")
    }

    ans := make_host_coherent_buffer(device_context, T, u32(image.width * image.height))

    copy_image_to_buffer(
        device_context,
        image.image,
        vk.ImageLayout.GENERAL,
        ans.buffer,
        u32(image.width),
        u32(image.height)
    )

    return ans
}

to_generic_buffer_storage_image :: proc(storage_image : ImageInfo) -> GenericResource
{
    ans := GenericBufferImage{}
    ans.image = storage_image.image
    ans.image_memory = storage_image.image_memory
    ans.image_view = storage_image.image_view
    ans.usage = storage_image.usage
    ans.layout = storage_image.layout
    return ans
}

delete_storeage_image :: proc(device_context : ^device.DeviceContext, storage_image : ImageInfo)
{
    vk.DestroyImageView(
        device_context.device,
        storage_image.image_view,
        nil
    )
    vk.FreeMemory(
        device_context.device,
        storage_image.image_memory,
        nil
    )
    vk.DestroyImage(
        device_context.device,
        storage_image.image,
        nil
    )
}
