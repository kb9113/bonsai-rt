package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

UniformBufferInfo :: struct($T: typeid)
{
    buffer : vk.Buffer,
    buffer_memory : vk.DeviceMemory,
    buffer_size : vk.DeviceSize,
    data : []T
}

make_uniform_buffer :: proc(
    device_context : ^device.DeviceContext, $T: typeid, n_elemements : u32
) -> UniformBufferInfo(T)
{
    ans := UniformBufferInfo(T){}
    ans.buffer_size = vk.DeviceSize(n_elemements * size_of(T))
    create_buffer(
        device_context,
        ans.buffer_size,
        {vk.BufferUsageFlag.UNIFORM_BUFFER},
        {vk.MemoryPropertyFlag.HOST_VISIBLE, vk.MemoryPropertyFlag.HOST_COHERENT},
        &ans.buffer,
        &ans.buffer_memory
    )

    raw_ptr_to_data : rawptr
    vk.MapMemory(
        device_context.device,
        ans.buffer_memory,
        0,
        ans.buffer_size,
        {},
        &raw_ptr_to_data
    )
    ans.data = slice.from_ptr(cast(^T)raw_ptr_to_data, int(n_elemements))
    return ans
}

to_generic_buffer_uniform_buffer :: proc(uniform_buffer : UniformBufferInfo($T)) -> GenericResource
{
    ans := GenericUniformBuffer{}
    ans.buffer = uniform_buffer.buffer
    ans.buffer_memory = uniform_buffer.buffer_memory
    ans.buffer_size = uniform_buffer.buffer_size
    return ans
}

delete_uniform_buffer :: proc(device_context : ^device.DeviceContext, uniform_buffer : UniformBufferInfo($T))
{
    vk.FreeMemory(device_context.device, uniform_buffer.buffer_memory, nil)
    vk.DestroyBuffer(device_context.device, uniform_buffer.buffer, nil)
}
