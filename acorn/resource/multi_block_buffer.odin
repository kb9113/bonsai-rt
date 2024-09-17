package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

Block :: struct
{
    start_index : u32,
    length : u32
}

MultiBlockBufferInfo :: struct($T: typeid)
{
    buffer : vk.Buffer,
    buffer_memory : vk.DeviceMemory,
    buffer_size : vk.DeviceSize,
    free_blocks : [dynamic]Block
}

make_multi_block_buffer :: proc(
    device_context : ^device.DeviceContext, $T: typeid, n_elemements : u32, additional_useage_flags : vk.BufferUsageFlags
) -> MultiBlockBufferInfo(T)
{
    ans := MultiBlockBufferInfo(T){}
    ans.buffer_size = vk.DeviceSize(n_elemements * size_of(T))
    ans.free_blocks = make([dynamic]Block)
    append(&ans.free_blocks, Block{0, n_elemements})
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

try_assign_block_in_multi_block_buffer :: proc(multi_block_buffer : ^MultiBlockBufferInfo($T), required_block_size : u32) -> (Block, bool)
{
    for i in 0..<len(multi_block_buffer.free_blocks)
    {
        if multi_block_buffer.free_blocks[i].length >= required_block_size
        {
            // we will use this block
            ans := Block{}
            ans.start_index = multi_block_buffer.free_blocks[i].start_index
            ans.length = required_block_size

            multi_block_buffer.free_blocks[i].start_index += required_block_size
            multi_block_buffer.free_blocks[i].length = multi_block_buffer.free_blocks[i].length - required_block_size

            return ans, true
        }
    }
    return Block{}, false
}

copy_host_cohernet_buffer_to_mult_block_buffer :: proc(
    device_context : ^device.DeviceContext,
    host_coherent_buffer : HostCoherhentBufferInfo($T),
    multi_block_buffer : ^MultiBlockBufferInfo(T)
) -> Block
{
    block, is_ok := try_assign_block_in_multi_block_buffer(multi_block_buffer, u32(len(host_coherent_buffer.data)))
    assert(is_ok, "could not find block large enough in buffer to copy")

    copy_buffer(
        device_context,
        host_coherent_buffer.buffer,
        multi_block_buffer.buffer,
        0,
        vk.DeviceSize(block.start_index * size_of(T)),
        host_coherent_buffer.buffer_size
    )

    return block
}

copy_host_cohernet_buffer_to_mult_block_buffer_block :: proc(
    device_context : ^device.DeviceContext,
    host_coherent_buffer : HostCoherhentBufferInfo($T),
    multi_block_buffer : ^MultiBlockBufferInfo(T),
    block : Block
)
{
    copy_buffer(
        device_context,
        host_coherent_buffer.buffer,
        multi_block_buffer.buffer,
        0,
        vk.DeviceSize(block.start_index * size_of(T)),
        host_coherent_buffer.buffer_size
    )
}

copy_block_out_to_new_buffer_host_cohearnnt :: proc(
    device_context : ^device.DeviceContext,
    multi_block_buffer : ^MultiBlockBufferInfo($T),
    block : Block
) -> HostCoherhentBufferInfo(T)
{
    host_coherent_buffer := make_host_coherent_buffer(
        device_context,
        T,
        u32(block.length)
    )
    copy_buffer(
        device_context,
        multi_block_buffer.buffer,
        host_coherent_buffer.buffer,
        vk.DeviceSize(block.start_index * size_of(T)),
        0,
        host_coherent_buffer.buffer_size
    )
    return host_coherent_buffer
}

remove_from_multiblock_buffer :: proc(multi_block_buffer : ^MultiBlockBufferInfo($T), block : Block)
{
    for i in 0..<len(multi_block_buffer.free_blocks)
    {
        if (multi_block_buffer.free_blocks[i].start_index + multi_block_buffer.free_blocks[i].length) == block.start_index
        {
            multi_block_buffer.free_blocks[i].length += block.length
            if (i + 1) < len(multi_block_buffer.free_blocks) &&
                (multi_block_buffer.free_blocks[i].start_index + multi_block_buffer.free_blocks[i].length) == multi_block_buffer.free_blocks[i + 1].start_index
            {
                multi_block_buffer.free_blocks[i].length += multi_block_buffer.free_blocks[i + 1].length
                ordered_remove(&multi_block_buffer.free_blocks, i + 1)
            }
            return
        }
    }
    append(&multi_block_buffer.free_blocks, block)
}

to_generic_buffer_multi_block_buffer :: proc(storage_buffer : MultiBlockBufferInfo($T)) -> GenericResource
{
    ans := GenericStorageBuffer{}
    ans.buffer = storage_buffer.buffer
    ans.buffer_memory = storage_buffer.buffer_memory
    ans.buffer_size = storage_buffer.buffer_size
    return ans
}

delete_multi_block_buffer :: proc(device_context : ^device.DeviceContext, multi_block_buffer : MultiBlockBufferInfo($T))
{
    vk.FreeMemory(device_context.device, multi_block_buffer.buffer_memory, nil)
    vk.DestroyBuffer(device_context.device, multi_block_buffer.buffer, nil)
    delete(multi_block_buffer.free_blocks)
}
