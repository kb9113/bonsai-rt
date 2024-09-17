package device
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"

CommandBufferContext :: struct
{
    command_pool : vk.CommandPool,
    command_buffer : vk.CommandBuffer
}

make_command_pool_and_buffer :: proc(device_context : ^DeviceContext) -> CommandBufferContext
{
    ans := CommandBufferContext{}

    queue_info := get_queue_info(
        device_context.physical_device,
        device_context.surface,
    )

    command_pool_create_info := vk.CommandPoolCreateInfo{}
    command_pool_create_info.sType = vk.StructureType.COMMAND_POOL_CREATE_INFO
    command_pool_create_info.flags = {vk.CommandPoolCreateFlag.RESET_COMMAND_BUFFER}
    command_pool_create_info.queueFamilyIndex = queue_info.graphics_family_index

    assert(
        vk.CreateCommandPool(
            device_context.device,
            &command_pool_create_info,
            nil,
            &ans.command_pool
        ) == vk.Result.SUCCESS
    )

    command_buf_allocation_info := vk.CommandBufferAllocateInfo{}
    command_buf_allocation_info.sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO
    command_buf_allocation_info.commandPool = ans.command_pool
    command_buf_allocation_info.level = vk.CommandBufferLevel.PRIMARY
    command_buf_allocation_info.commandBufferCount = 1

    assert(
        vk.AllocateCommandBuffers(
            device_context.device,
            &command_buf_allocation_info,
            &ans.command_buffer
        ) == vk.Result.SUCCESS
    )

    return ans
}

delete_command_pool_and_buffer :: proc(device_context : ^DeviceContext, command_buffer : CommandBufferContext)
{
    command_buffer_copy := command_buffer.command_buffer
    vk.FreeCommandBuffers(
        device_context.device,
        command_buffer.command_pool,
        1,
        &command_buffer_copy
    )
    vk.DestroyCommandPool(
        device_context.device,
        command_buffer.command_pool,
        nil
    )
}
