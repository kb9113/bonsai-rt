package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

delete_resource :: proc{
    delete_host_cohearnent_buffer,
    delete_storage_buffer,
    delete_serial_buffer,
    delete_uniform_buffer,
    delete_multi_block_buffer,
    delete_acceleration_structure,
    delete_sampler,
    delete_storeage_image,
}

// =================
// helper functions
// =================
copy_buffer :: proc(
    device_context : ^device.DeviceContext,
    src_buffer : vk.Buffer,
    dst_buffer : vk.Buffer,
    src_offset : vk.DeviceSize,
    dst_offset : vk.DeviceSize,
    size : vk.DeviceSize
)
{
    command_buffer := device.begin_single_time_command(device_context)

    copy_region := vk.BufferCopy{}
    copy_region.srcOffset = src_offset
    copy_region.dstOffset = dst_offset
    copy_region.size = size
    vk.CmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region)

    device.end_single_time_command(device_context, &command_buffer)
}

find_memory_type :: proc(device_context : ^device.DeviceContext, type_filter : u32, properites : vk.MemoryPropertyFlags) -> u32
{
    mem_properties := vk.PhysicalDeviceMemoryProperties{}
    vk.GetPhysicalDeviceMemoryProperties(device_context.physical_device, &mem_properties)

    for i in 0..<mem_properties.memoryTypeCount
    {
        if (type_filter & (1 << i)) > 0 &&
            mem_properties.memoryTypes[i].propertyFlags >= properites
        {
            return i
        }
    }

    panic("failed find memory")
}

create_buffer :: proc(
    device_context : ^device.DeviceContext,
    size : vk.DeviceSize,
    useage : vk.BufferUsageFlags,
    properties : vk.MemoryPropertyFlags,
    buffer : ^vk.Buffer,
    buffer_memory : ^vk.DeviceMemory
)
{
    assert(size != 0)

    vertex_buffer_create_info := vk.BufferCreateInfo{}
    vertex_buffer_create_info.sType = vk.StructureType.BUFFER_CREATE_INFO
    vertex_buffer_create_info.size = size
    vertex_buffer_create_info.usage = useage
    vertex_buffer_create_info.sharingMode = vk.SharingMode.EXCLUSIVE

    assert(
        vk.CreateBuffer(device_context.device, &vertex_buffer_create_info, nil, buffer) ==
        vk.Result.SUCCESS
    )

    mem_requirements := vk.MemoryRequirements{}
    vk.GetBufferMemoryRequirements(device_context.device, buffer^, &mem_requirements)

    allocaton_info := vk.MemoryAllocateInfo{}
    allocaton_info.sType = vk.StructureType.MEMORY_ALLOCATE_INFO
    allocaton_info.allocationSize = mem_requirements.size
    allocaton_info.memoryTypeIndex = find_memory_type(
        device_context,
        mem_requirements.memoryTypeBits,
        properties
    )

    allocaton_flags_info := vk.MemoryAllocateFlagsInfo{}
    if vk.BufferUsageFlag.SHADER_DEVICE_ADDRESS in useage
    {
        allocaton_flags_info.sType = vk.StructureType.MEMORY_ALLOCATE_FLAGS_INFO
        allocaton_flags_info.flags = {vk.MemoryAllocateFlag.DEVICE_ADDRESS}
        allocaton_info.pNext = &allocaton_flags_info
    }

    assert(
        vk.AllocateMemory(device_context.device, &allocaton_info, nil, buffer_memory) ==
        vk.Result.SUCCESS,
        "memory allocation failed"
    )
    vk.BindBufferMemory(device_context.device, buffer^, buffer_memory^, 0)

}

create_image :: proc(
    device_context : ^device.DeviceContext,
    width : u32, height : u32,
    format : vk.Format,
    tiling : vk.ImageTiling,
    usage : vk.ImageUsageFlags,
    properties : vk.MemoryPropertyFlags,
    initial_layout : vk.ImageLayout,
    image : ^vk.Image,
    image_memory : ^vk.DeviceMemory
)
{
    image_create_info := vk.ImageCreateInfo{}
    image_create_info.sType = vk.StructureType.IMAGE_CREATE_INFO
    image_create_info.imageType = vk.ImageType.D2
    image_create_info.extent.width = width
    image_create_info.extent.height = height
    image_create_info.extent.depth = 1
    image_create_info.mipLevels = 1
    image_create_info.arrayLayers = 1
    image_create_info.format = format
    image_create_info.tiling = tiling
    image_create_info.initialLayout = initial_layout
    image_create_info.usage = usage
    image_create_info.sharingMode = vk.SharingMode.EXCLUSIVE
    image_create_info.samples = {vk.SampleCountFlag._1}
    image_create_info.flags = {}

    if vk.CreateImage(device_context.device, &image_create_info, nil, image) != vk.Result.SUCCESS
    {
        panic("could not create image")
    }

    mem_requirements := vk.MemoryRequirements{}
    vk.GetImageMemoryRequirements(device_context.device, image^, &mem_requirements)

    allocation_info := vk.MemoryAllocateInfo{}
    allocation_info.sType = vk.StructureType.MEMORY_ALLOCATE_INFO
    allocation_info.allocationSize = mem_requirements.size
    allocation_info.memoryTypeIndex = find_memory_type(device_context, mem_requirements.memoryTypeBits, properties)

    if vk.AllocateMemory(device_context.device, &allocation_info, nil, image_memory) != vk.Result.SUCCESS
    {
        fmt.println("failed to alloc memory")
        return
    }

    vk.BindImageMemory(device_context.device, image^, image_memory^, 0)
}

copy_buffer_to_image:: proc(device_context : ^device.DeviceContext, buffer : vk.Buffer, image : vk.Image, width : u32, height : u32)
{
    command_buffer := device.begin_single_time_command(device_context)

    buffer_image_copy := vk.BufferImageCopy{}
    buffer_image_copy.bufferOffset = 0;
    buffer_image_copy.bufferRowLength = 0;
    buffer_image_copy.bufferImageHeight = 0;

    buffer_image_copy.imageSubresource.aspectMask = {vk.ImageAspectFlag.COLOR};
    buffer_image_copy.imageSubresource.mipLevel = 0;
    buffer_image_copy.imageSubresource.baseArrayLayer = 0;
    buffer_image_copy.imageSubresource.layerCount = 1;

    buffer_image_copy.imageOffset = vk.Offset3D{0, 0, 0};
    buffer_image_copy.imageExtent = vk.Extent3D{
        width,
        height,
        1
    };

    vk.CmdCopyBufferToImage(
        command_buffer,
        buffer,
        image,
        vk.ImageLayout.TRANSFER_DST_OPTIMAL,
        1,
        &buffer_image_copy
    )

    device.end_single_time_command(device_context, &command_buffer)
}

copy_image_to_buffer :: proc(
    device_context : ^device.DeviceContext, image : vk.Image, image_layout : vk.ImageLayout,
    buffer : vk.Buffer, width : u32, height : u32
)
{
    command_buffer := device.begin_single_time_command(device_context)

    buffer_image_copy := vk.BufferImageCopy{}
    buffer_image_copy.bufferOffset = 0;
    buffer_image_copy.bufferRowLength = 0;
    buffer_image_copy.bufferImageHeight = 0;

    buffer_image_copy.imageSubresource.aspectMask = {vk.ImageAspectFlag.COLOR};
    buffer_image_copy.imageSubresource.mipLevel = 0;
    buffer_image_copy.imageSubresource.baseArrayLayer = 0;
    buffer_image_copy.imageSubresource.layerCount = 1;

    buffer_image_copy.imageOffset = vk.Offset3D{0, 0, 0};
    buffer_image_copy.imageExtent = vk.Extent3D{
        width,
        height,
        1
    };

    vk.CmdCopyImageToBuffer(
        command_buffer,
        image,
        image_layout,
        buffer,
        1,
        &buffer_image_copy
    )

    device.end_single_time_command(device_context, &command_buffer)
}
