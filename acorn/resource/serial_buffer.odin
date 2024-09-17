package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

SerialBufferInfo :: struct($T: typeid)
{
    storage_buffer : StorageBufferInfo(T),
    single_item_host_coherent_buffer : HostCoherhentBufferInfo(T),
    length : u32,
}

make_serial_buffer :: proc(
    device_context : ^device.DeviceContext, $T: typeid, n_elemements_capacity : u32
) -> SerialBufferInfo(T)
{
    ans := SerialBufferInfo(T){}
    ans.storage_buffer = make_storage_buffer(
        device_context,
        T, n_elemements_capacity,
        {vk.BufferUsageFlag.TRANSFER_DST, vk.BufferUsageFlag.TRANSFER_SRC}
    )
    ans.single_item_host_coherent_buffer = make_host_coherent_buffer(
        device_context,
        T, 1
    )
    ans.length = 0
    return ans
}

append_to_serial_buffer :: proc(
    device_context : ^device.DeviceContext,
    serial_buffer : ^SerialBufferInfo($T),
    item : T
)
{
    serial_buffer.single_item_host_coherent_buffer.data[0] = item
    copy_host_cohernet_buffer_to_storage_buffer(
        device_context,
        serial_buffer.single_item_host_coherent_buffer,
        serial_buffer.storage_buffer,
        0,
        vk.DeviceSize(serial_buffer.length)
    )
    serial_buffer.length += 1
}

remove_index_from_serial_buffer :: proc(
    device_context : ^device.DeviceContext,
    serial_buffer : ^SerialBufferInfo($T),
    index_to_remove : u32
)
{
    copy_storage_buffer_to_host_coherent_buffer(
        device_context,
        serial_buffer.storage_buffer,
        serial_buffer.single_item_host_coherent_buffer,
        vk.DeviceSize(serial_buffer.length - 1),
        0,
        1
    )
    copy_host_cohernet_buffer_to_storage_buffer(
        device_context,
        serial_buffer.single_item_host_coherent_buffer,
        serial_buffer.storage_buffer,
        0,
        vk.DeviceSize(index_to_remove)
    )
    serial_buffer.length -= 1
}

to_generic_buffer_serial_buffer :: proc(serial_buffer : SerialBufferInfo($T)) -> GenericResource
{
    return to_generic_buffer_storage_buffer(serial_buffer.storage_buffer)
}

delete_serial_buffer :: proc(device_context : ^device.DeviceContext, serial_buffer : SerialBufferInfo($T))
{
    delete_storage_buffer(device_context, serial_buffer.storage_buffer)
    delete_host_cohearnent_buffer(device_context, serial_buffer.single_item_host_coherent_buffer)
}
