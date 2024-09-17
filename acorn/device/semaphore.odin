package device
import vk "vendor:vulkan"
import "core:c/libc"
import "core:fmt"
import "vendor:stb/image"
import "core:math"
import sdl "vendor:sdl2"

create_semaphore :: proc(device_context : ^DeviceContext) -> vk.Semaphore
{
    ans := vk.Semaphore{}
    semaphore_info := vk.SemaphoreCreateInfo{}
    semaphore_info.sType = vk.StructureType.SEMAPHORE_CREATE_INFO
    assert(
        vk.CreateSemaphore(
            device_context.device, &semaphore_info, nil, &ans
        ) == vk.Result.SUCCESS
    )
    return ans
}

delete_semaphore :: proc(device_context : ^DeviceContext, sem : vk.Semaphore)
{
    vk.DestroySemaphore(
        device_context.device,
        sem,
        nil
    )
}
