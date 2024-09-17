package geometry

import vk "vendor:vulkan"
import "../acorn/device"
import "../acorn/resource"
import "../acorn/pipeline"
import "../acorn/shader_group"
import "../acorn/shader_module"
import "../acorn/descriptor_set"
import "../acorn/present"
import "../color"
import "../scene"
import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import "vendor:stb/image"
import "core:slice"
import "core:strings"
import "core:strconv"

GPUMaterial :: struct #packed
{
    spoly_color : [3]f32,
    material_type : u32,
    args : [4]f32
}

GPUInstanceInfo :: struct #packed
{
    transform : matrix[4, 4]f32,
    index_buffer_start_index : u32,
    index_buffer_length : u32,
    vertex_buffer_start_index : u32,
    vertex_buffer_length : u32,
}

GPULight :: struct #packed
{
    type : u32,
    arg0 : u32,
    arg1 : u32,
    arg2 : u32,
}

GPURenderInfo :: struct #packed
{
    max_depth : u32,
    n_lights : u32,
}

GeometryContext :: struct
{
    scene : scene.Scene,

    compute_shader_group : shader_group.ShaderGroupContext,
    compute_pipeline : pipeline.ComputePipelineContext,
    compute_descriptor_set : descriptor_set.DescriptorSetContext,

    blend_shader_group : shader_group.ShaderGroupContext,
    blend_pipeline : pipeline.ComputePipelineContext,
    blend_descriptor_set : descriptor_set.DescriptorSetContext,

    camera_buffer : resource.UniformBufferInfo(matrix[4, 4]f32),
    rnd_seed_buffer : resource.UniformBufferInfo(u32),
    frame_number_buffer : resource.UniformBufferInfo(u32),
    render_info_buffer : resource.UniformBufferInfo(GPURenderInfo),

    top_level_acceleration_structure : resource.AccelerationStructure,
    vertex_multiblock_buffer : resource.MultiBlockBufferInfo([4]f32),
    index_multiblock_buffer : resource.MultiBlockBufferInfo(u32),
    geometry_info_buffer : resource.StorageBufferInfo(GPUInstanceInfo),
    material_buffer : resource.StorageBufferInfo(GPUMaterial),
    light_buffer : resource.StorageBufferInfo(GPULight),

    xyz_ray_trace_image : resource.ImageInfo,
    xyz_blend_image : resource.ImageInfo,
    output_image : resource.ImageInfo,
}

make_geometry :: proc(device_context : ^device.DeviceContext) -> GeometryContext
{
    ans := GeometryContext{}
    ans.compute_shader_group = shader_group.make_shader_group(
        device_context,
        []shader_module.ShaderModuleContext{
            shader_module.create_shader_module(
                device_context,
                "shaders/integrators/nee.slang",
                "shaders/_spirv/nee.spv",
                .COMPUTE
            )
        },
        1
    )

    ans.compute_pipeline = pipeline.create_compute_pipeline(
        device_context,
        ans.compute_shader_group
    )

    ans.compute_descriptor_set = descriptor_set.allocate_descriptor_set(
        device_context,
        &ans.compute_shader_group,
        0
    )

    ans.blend_shader_group = shader_group.make_shader_group(
        device_context,
        []shader_module.ShaderModuleContext{
            shader_module.create_shader_module(
                device_context,
                "shaders/blend_frames.slang",
                "shaders/_spirv/blend_frames.spv",
                .COMPUTE
            )
        },
        1
    )

    ans.blend_pipeline = pipeline.create_compute_pipeline(
        device_context,
        ans.blend_shader_group
    )

    ans.blend_descriptor_set = descriptor_set.allocate_descriptor_set(
        device_context,
        &ans.blend_shader_group,
        0
    )

    ans.camera_buffer = resource.make_uniform_buffer(
        device_context, matrix[4, 4]f32, 1
    )
    ans.rnd_seed_buffer = resource.make_uniform_buffer(
        device_context, u32, 1
    )
    ans.frame_number_buffer = resource.make_uniform_buffer(
        device_context, u32, 1
    )
    ans.render_info_buffer = resource.make_uniform_buffer(
        device_context, GPURenderInfo, 1
    )

    ans.xyz_ray_trace_image = resource.make_image(
        device_context,
        vk.DeviceSize(device_context.swap_chain.swap_chain_extent.width),
        vk.DeviceSize(device_context.swap_chain.swap_chain_extent.height),
        {vk.SampleCountFlag._1},
        {vk.ImageUsageFlag.STORAGE, vk.ImageUsageFlag.COLOR_ATTACHMENT, vk.ImageUsageFlag.TRANSFER_DST, vk.ImageUsageFlag.TRANSFER_SRC},
        vk.Format.R32G32B32A32_SFLOAT,
        vk.ImageTiling.OPTIMAL,
        {vk.ImageAspectFlag.COLOR}
    )
    resource.transition_image_layout(
        device_context,
        &ans.xyz_ray_trace_image,
        vk.ImageLayout.GENERAL
    )

    ans.xyz_blend_image = resource.make_image(
        device_context,
        vk.DeviceSize(device_context.swap_chain.swap_chain_extent.width),
        vk.DeviceSize(device_context.swap_chain.swap_chain_extent.height),
        {vk.SampleCountFlag._1},
        {vk.ImageUsageFlag.STORAGE, vk.ImageUsageFlag.COLOR_ATTACHMENT, vk.ImageUsageFlag.TRANSFER_DST, vk.ImageUsageFlag.TRANSFER_SRC},
        vk.Format.R32G32B32A32_SFLOAT,
        vk.ImageTiling.OPTIMAL,
        {vk.ImageAspectFlag.COLOR}
    )
    resource.transition_image_layout(
        device_context,
        &ans.xyz_blend_image,
        vk.ImageLayout.GENERAL
    )

    ans.output_image = resource.make_image(
        device_context,
        vk.DeviceSize(device_context.swap_chain.swap_chain_extent.width),
        vk.DeviceSize(device_context.swap_chain.swap_chain_extent.height),
        {vk.SampleCountFlag._1},
        {vk.ImageUsageFlag.STORAGE, vk.ImageUsageFlag.COLOR_ATTACHMENT, vk.ImageUsageFlag.TRANSFER_DST, vk.ImageUsageFlag.TRANSFER_SRC},
        vk.Format.R32G32B32A32_SFLOAT,
        vk.ImageTiling.OPTIMAL,
        {vk.ImageAspectFlag.COLOR}
    )
    resource.transition_image_layout(
        device_context,
        &ans.output_image,
        vk.ImageLayout.GENERAL
    )

    return ans
}

render :: proc(
    device_context : ^device.DeviceContext,
    geometry_context : ^GeometryContext
)
{
    for frame_number in 1..=geometry_context.scene.settings.n_samples
    {
        geometry_context.rnd_seed_buffer.data[0] = rand.uint32()
        geometry_context.frame_number_buffer.data[0] = frame_number

        descriptor_set.update_descriptor_set(
            device_context,
            geometry_context.compute_descriptor_set,
            []descriptor_set.InputBinding{
                descriptor_set.make_input_binding(0, 0, geometry_context.top_level_acceleration_structure),
                descriptor_set.make_input_binding(1, 0, geometry_context.camera_buffer),
                descriptor_set.make_input_binding(2, 0, geometry_context.xyz_ray_trace_image),
                descriptor_set.make_input_binding(3, 0, geometry_context.material_buffer),
                descriptor_set.make_input_binding(4, 0, geometry_context.rnd_seed_buffer),
                descriptor_set.make_input_binding(5, 0, geometry_context.vertex_multiblock_buffer),
                descriptor_set.make_input_binding(6, 0, geometry_context.index_multiblock_buffer),
                descriptor_set.make_input_binding(7, 0, geometry_context.geometry_info_buffer),
                descriptor_set.make_input_binding(8, 0, geometry_context.light_buffer),
                descriptor_set.make_input_binding(9, 0, geometry_context.render_info_buffer),
            }
        )

        pipeline.invoke_compute_pipeline(
            device_context,
            &geometry_context.compute_pipeline,
            []descriptor_set.DescriptorSetContext{
                geometry_context.compute_descriptor_set
            },
            [3]u32{u32(device_context.width) / 8, u32(device_context.height) / 8, 1}
        )

        vk.QueueWaitIdle(device_context.graphics_queue)

        descriptor_set.update_descriptor_set(
            device_context,
            geometry_context.blend_descriptor_set,
            []descriptor_set.InputBinding{
                descriptor_set.make_input_binding(0, 0, geometry_context.xyz_ray_trace_image),
                descriptor_set.make_input_binding(1, 0, geometry_context.xyz_blend_image),
                descriptor_set.make_input_binding(2, 0, geometry_context.output_image),
                descriptor_set.make_input_binding(3, 0, geometry_context.frame_number_buffer),
            }
        )

        pipeline.invoke_compute_pipeline(
            device_context,
            &geometry_context.blend_pipeline,
            []descriptor_set.DescriptorSetContext{
                geometry_context.blend_descriptor_set
            },
            [3]u32{u32(device_context.width) / 8, u32(device_context.height) / 8, 1}
        )

        vk.QueueWaitIdle(device_context.graphics_queue)

        if frame_number % 512 == 0
        {
            swap_chain_image_index, image_avail_semaphore := device.get_next_swap_chain_image(
                device_context
            )

            present.present_image(
                device_context,
                geometry_context.output_image,
                swap_chain_image_index,
                []vk.Semaphore{
                    image_avail_semaphore
                }
            )
        }
    }
}

save_output_image_to_file :: proc(
    device_context : ^device.DeviceContext,
    geometry_context : ^GeometryContext,
    path : string
)
{
    host_cohearnet_buffer := resource.copy_image_to_new_host_coherent_buffer(
        device_context,
        [4]f32,
        geometry_context.output_image
    )

    gamma_corrected_image := make([][3]u8, len(host_cohearnet_buffer.data))
    for i in 0..<len(host_cohearnet_buffer.data)
    {
        color_linear_rgb := color.LinearRGBColor{
            f64(host_cohearnet_buffer.data[i].r),
            f64(host_cohearnet_buffer.data[i].g),
            f64(host_cohearnet_buffer.data[i].b)
        }
        color_srgb := color.linear_rgb_to_srgb(color_linear_rgb)
        color_srgbu8 := color.srgb_to_srgbu8(color_srgb)
        gamma_corrected_image[i].r = color_srgbu8.r
        gamma_corrected_image[i].g = color_srgbu8.g
        gamma_corrected_image[i].b = color_srgbu8.b
    }

    image.write_png(
        strings.clone_to_cstring(path), device_context.width, device_context.height,
        3, rawptr(raw_data(gamma_corrected_image)),
        device_context.width * 3
    )
}
