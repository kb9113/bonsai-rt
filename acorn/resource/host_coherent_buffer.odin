package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

HostCoherhentBufferInfo :: struct($T: typeid)
{
    buffer : vk.Buffer,
    buffer_memory : vk.DeviceMemory,
    buffer_size : vk.DeviceSize,
    data : []T
}

make_host_coherent_buffer :: proc(
    device_context : ^device.DeviceContext, $T: typeid, n_elemements : u32
) -> HostCoherhentBufferInfo(T)
{
    ans := HostCoherhentBufferInfo(T){}
    ans.buffer_size = vk.DeviceSize(n_elemements * size_of(T))
    create_buffer(
        device_context,
        ans.buffer_size,
        {vk.BufferUsageFlag.TRANSFER_SRC, vk.BufferUsageFlag.TRANSFER_DST},
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

delete_host_cohearnent_buffer :: proc(device_context : ^device.DeviceContext, uniform_buffer : HostCoherhentBufferInfo($T))
{
    vk.FreeMemory(device_context.device, uniform_buffer.buffer_memory, nil)
    vk.DestroyBuffer(device_context.device, uniform_buffer.buffer, nil)
}
