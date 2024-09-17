# Acorn
This is a wrapper around vulkan used by bonsai_rt

## Resources
## Device
a device consits a vulkan device, queues, swap chain, sdl2 window and a command pool
```odin
device_context := device.make_device(
    true,
    device.std_ray_trace_feature_set(),
    "test",
    1024, 1024
)
```

### Uniform Buffer
a host cohearent buffer for uniforms on the gpu
```odin
buffer := resource.make_uniform_buffer(&device, u32, 1)
delete_resource(buffer)
```
### Host Cohearent Buffer
a host cohearent buffer usually for copying into a on device buffer
```odin
buffer := resource.make_host_coherent_buffer(&device, u32, 64)
delete_resource(buffer)
```
### Storage Buffer
an on device buffer
```odin
buffer := resource.make_storage_buffer(&device, u32, 64, {vk.BufferUsageFlag.TRANSFER_DST})
delete_resource(buffer)
```
### Multi Block Buffer
an on device buffer that mannages its own blocks so that multiple segments of data can be uploaded to it
```odin
buffer := resource.make_multi_block_buffer(&device, u32, 64)
delete_resource(buffer)
```
### Sampler
```odin
sampler := resource.make_sampler(&device)
delete_resource(sampler)
```
### Image
```odin
image := resource.make_image(
    &device, 1920, 1080,
    {vk.SampleCountFlag._1},
    {vk.ImageUsageFlag.STORAGE, vk.ImageUsageFlag.COLOR_ATTACHMENT, vk.ImageUsageFlag.TRANSFER_DST, vk.ImageUsageFlag.TRANSFER_SRC},
    vk.Format.R32G32B32A32_SFLOAT,
    vk.ImageTiling.OPTIMAL,
    {vk.ImageAspectFlag.COLOR}
)
delete_resource(image)
```
### RayAcceleration Structure
```odin
bottom_level_acceleration_structure = resource.create_bottom_level_acceleration_structure(
    &device,
    vertex_storeage_buffer,
    index_storeage_buffer
)
top_level_acceleration_structure = resource.create_top_level_acceleration_structure(
    device_context,
    []resource.AccelerationStructureInstance{
        resource.AccelerationStructureInstance{
            bottom_level_acceleration_structure,
            matrix[4, 4]f32{
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1
            }
        }
    }
)
delete_resource(bottom_level_acceleration_structure)
delete_resource(top_level_acceleration_structure)
```

## Invoking - Compute Full Example
main.odin
```odin
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
```
test.slang
```hlsl
[[vk::binding(0, 0)]]
RWStructuredBuffer<uint> values_in;

[[vk::binding(1, 0)]]
RWStructuredBuffer<uint> values_out;

[shader("compute")]
[numthreads(64,1,1)]
void computeMain(uint3 pixel_index : SV_DispatchThreadID)
{
    values_out[pixel_index.x] = 2 * values_in[pixel_index.x];
}
```
