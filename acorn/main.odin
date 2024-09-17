package main
import vk "vendor:vulkan"
import "./device"
import "./resource"
import "./pipeline"
import "./shader_module"
import "./shader_group"
import "./descriptor_set"
import "core:fmt"

main :: proc()
{
    device_context := device.make_device(
        true,
        device.std_ray_trace_feature_set(),
        "test",
        1024, 1024
    )

    test_shader_module := shader_module.create_shader_module(
        &device_context,
        "test.slang",
        "test.spv",
        .COMPUTE
    )

    compute_shader_group := shader_group.make_shader_group(
        &device_context,
        []shader_module.ShaderModuleContext{test_shader_module},
        1
    )

    compute_pipeline := pipeline.create_compute_pipeline(
        &device_context,
        compute_shader_group
    )

    compute_descriptor_set := descriptor_set.allocate_descriptor_set(
        &device_context,
        &compute_shader_group,
        0
    )

    buffer1 := resource.make_storage_buffer(&device_context, u32, 64, {vk.BufferUsageFlag.TRANSFER_DST})
    buffer2 := resource.make_storage_buffer(&device_context, u32, 64, {vk.BufferUsageFlag.TRANSFER_SRC})

    host_coherent_buffer := resource.make_host_coherent_buffer(&device_context, u32, 64)
    for i in 0..<64
    {
        host_coherent_buffer.data[i] = u32(i)
    }

    resource.copy_host_cohernet_buffer_to_storage_buffer(&device_context, host_coherent_buffer, buffer1)
    fmt.println(host_coherent_buffer.data)

    descriptor_set.update_descriptor_set(
        &device_context,
        compute_descriptor_set,
        []descriptor_set.InputBinding{
            descriptor_set.make_input_binding(0, 0, buffer1),
            descriptor_set.make_input_binding(1, 0, buffer2)
        }
    )


    pipeline.invoke_compute_pipeline(
        &device_context, &compute_pipeline,
        []descriptor_set.DescriptorSetContext{compute_descriptor_set},
        [3]u32{1, 1, 1}
    )

    host_coherent_data_out := resource.copy_storage_buffer_to_new_host_coherent_buffer(
        &device_context, buffer2
    )
    fmt.println(host_coherent_data_out.data)

    resource.delete_resource(&device_context, buffer1)
    resource.delete_resource(&device_context, buffer2)
    resource.delete_resource(&device_context, host_coherent_buffer)
    resource.delete_resource(&device_context, host_coherent_data_out)

    pipeline.delete_compute_pipeline(&device_context, compute_pipeline)
    shader_group.delete_shader_group(&device_context, compute_shader_group)
    shader_module.delete_shader_module(&device_context, test_shader_module)
    device.delete_device(device_context)
}
