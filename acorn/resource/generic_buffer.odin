package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

GenericResource :: union
{
    GenericStorageBuffer,
    GenericUniformBuffer,
    GenericBufferImage,
    GenericSampler,
    GenericAccelerationStructure
}

GenericStorageBuffer :: struct
{
    buffer : vk.Buffer,
    buffer_memory : vk.DeviceMemory,
    buffer_size : vk.DeviceSize
}

GenericUniformBuffer :: struct
{
    buffer : vk.Buffer,
    buffer_memory : vk.DeviceMemory,
    buffer_size : vk.DeviceSize
}

GenericBufferImage :: struct
{
    image : vk.Image,
    image_memory : vk.DeviceMemory,
    image_view : vk.ImageView,
    usage : vk.ImageUsageFlags,
    layout : vk.ImageLayout
}

GenericSampler :: struct
{
    sampler : vk.Sampler
}

GenericAccelerationStructure :: struct
{
    acceleration_structure : vk.AccelerationStructureKHR
}

to_generic_buffer :: proc{
    to_generic_buffer_storage_buffer,
    to_generic_buffer_uniform_buffer,
    to_generic_buffer_storage_image,
    to_generic_buffer_multi_block_buffer,
    to_generic_buffer_serial_buffer,
    to_generic_buffer_sampler,
    to_generic_buffer_acceleration_structure,
}

generic_buffer_vk_buffer :: proc(generic_buffer : GenericResource) -> vk.Buffer
{
    switch v in generic_buffer
    {
        case GenericStorageBuffer: return v.buffer
        case GenericUniformBuffer: return v.buffer
        case GenericBufferImage: panic("cannot convert image to vk buffer")
        case GenericSampler: panic("cannot convert sampler to vk buffer")
        case GenericAccelerationStructure: panic("cannot convert acceleration structure to buffer")
    }
    panic("cannot convert image to vk buffer")
}
