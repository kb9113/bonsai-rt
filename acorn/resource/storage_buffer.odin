package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

/*
Storage buffer is a no frils buffer that lives on the gpu

*/

StorageBufferInfo :: struct($T: typeid)
{
    buffer : vk.Buffer,
    buffer_memory : vk.DeviceMemory,
    buffer_size : vk.DeviceSize
}

make_storage_buffer :: proc(
    device_context : ^device.DeviceContext, $T: typeid, n_elemements : u32, additional_useage_flags : vk.BufferUsageFlags
) -> StorageBufferInfo(T)
{
    ans := StorageBufferInfo(T){}
    ans.buffer_size = vk.DeviceSize(n_elemements * size_of(T))
    create_buffer(
        device_context,
        ans.buffer_size,
        {vk.BufferUsageFlag.STORAGE_BUFFER} | additional_useage_flags,
        {vk.MemoryPropertyFlag.DEVICE_LOCAL},
        &ans.buffer,
        &ans.buffer_memory
    )
    return ans
}

copy_host_cohernet_buffer_to_storage_buffer :: proc(
    device_context : ^device.DeviceContext,
    host_coherent_buffer : HostCoherhentBufferInfo($T),
    storeage_buffer : StorageBufferInfo(T),
    src_elem_offset : vk.DeviceSize = 0,
    dst_elem_offset : vk.DeviceSize = 0
)
{
    assert(
        src_elem_offset * size_of(T) + host_coherent_buffer.buffer_size <=
        dst_elem_offset * size_of(T) + storeage_buffer.buffer_size,
        "buffer does not fit"
    )
    copy_buffer(
        device_context,
        host_coherent_buffer.buffer,
        storeage_buffer.buffer,
        src_elem_offset * size_of(T),
        dst_elem_offset * size_of(T),
        host_coherent_buffer.buffer_size
    )
}

copy_storeage_buffer_to_storeage_buffer :: proc(
    device_context : ^device.DeviceContext,
    storeage_buffer1 : StorageBufferInfo($T),
    storeage_buffer2 : StorageBufferInfo(T)
)
{
    copy_buffer(
        device_context,
        storeage_buffer1.buffer,
        storeage_buffer2.buffer,
        0,
        0,
        storeage_buffer1.buffer_size
    )
}

copy_storage_buffer_to_new_host_coherent_buffer :: proc(
    device_context : ^device.DeviceContext,
    storeage_buffer : StorageBufferInfo($T)
) -> HostCoherhentBufferInfo(T)
{
    ans := make_host_coherent_buffer(device_context, T, u32(storeage_buffer.buffer_size / size_of(T)))
    copy_buffer(
        device_context,
        storeage_buffer.buffer,
        ans.buffer,
        0,
        0,
        storeage_buffer.buffer_size
    )
    return ans
}

copy_storage_buffer_to_host_coherent_buffer :: proc(
    device_context : ^device.DeviceContext,
    storeage_buffer : StorageBufferInfo($T),
    host_cohearent_buffer : HostCoherhentBufferInfo(T),
    src_elem_offset : vk.DeviceSize = 0,
    dst_elem_offset : vk.DeviceSize = 0,
    n_elems : vk.DeviceSize = 1
)
{
    copy_buffer(
        device_context,
        storeage_buffer.buffer,
        host_cohearent_buffer.buffer,
        src_elem_offset * size_of(T),
        dst_elem_offset * size_of(T),
        n_elems * size_of(T)
    )
}

to_generic_buffer_storage_buffer :: proc(storage_buffer : StorageBufferInfo($T)) -> GenericResource
{
    ans := GenericStorageBuffer{}
    ans.buffer = storage_buffer.buffer
    ans.buffer_memory = storage_buffer.buffer_memory
    ans.buffer_size = storage_buffer.buffer_size
    return ans
}

elem_len :: proc(storage_buffer : StorageBufferInfo($T)) -> u32
{
    return u32(storage_buffer.buffer_size / size_of(T))
}

delete_storage_buffer :: proc(device_context : ^device.DeviceContext, serial_buffer : StorageBufferInfo($T))
{
    vk.FreeMemory(device_context.device, serial_buffer.buffer_memory, nil)
    vk.DestroyBuffer(device_context.device, serial_buffer.buffer, nil)
}
