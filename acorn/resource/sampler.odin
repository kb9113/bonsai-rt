package resource
import vk "vendor:vulkan"
import "core:fmt"
import "core:slice"
import "core:c/libc"
import "core:mem"
import "../device"

SamplerInfo :: struct
{
    sampler : vk.Sampler
}

make_sampler :: proc(device_context : ^device.DeviceContext) -> SamplerInfo
{
    sampler_create_info := vk.SamplerCreateInfo{}
    sampler_create_info.sType = vk.StructureType.SAMPLER_CREATE_INFO
    sampler_create_info.magFilter = vk.Filter.LINEAR
    sampler_create_info.minFilter = vk.Filter.LINEAR

    sampler_create_info.addressModeU = vk.SamplerAddressMode.REPEAT
    sampler_create_info.addressModeV = vk.SamplerAddressMode.REPEAT
    sampler_create_info.addressModeW = vk.SamplerAddressMode.REPEAT

    sampler_create_info.anisotropyEnable = true
    sampler_create_info.maxAnisotropy = device.get_sampler_max_anisotropy(device_context)

    sampler_create_info.borderColor = vk.BorderColor.INT_OPAQUE_BLACK
    sampler_create_info.unnormalizedCoordinates = false

    sampler_create_info.compareEnable = false
    sampler_create_info.compareOp = vk.CompareOp.ALWAYS

    sampler_create_info.mipmapMode = vk.SamplerMipmapMode.LINEAR
    sampler_create_info.mipLodBias = 0
    sampler_create_info.minLod = 0
    sampler_create_info.maxLod = 0

    ans := SamplerInfo{}
    assert(
        vk.CreateSampler(
            device_context.device,
            &sampler_create_info,
            nil,
            &ans.sampler
        ) == vk.Result.SUCCESS
    )
    return ans
}

to_generic_buffer_sampler :: proc(sampler : SamplerInfo) -> GenericSampler
{
    ans := GenericSampler{}
    ans.sampler = sampler.sampler
    return ans
}

delete_sampler :: proc(device_context : ^device.DeviceContext, sampler : SamplerInfo)
{
    vk.DestroySampler(
        device_context.device,
        sampler.sampler,
        nil
    )
}
