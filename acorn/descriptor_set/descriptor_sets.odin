package descriptor_set
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:log"
import "core:math"
import "core:slice"
import "core:time"
import "../scan"
import "../resource"
import "../device"
import "../shader_module"
import "../shader_group"

make_input_binding :: proc(
    binding_number : u32, set_number : u32,
    b : $T
) -> InputBinding
{
    ans := InputBinding{}
    ans.binding_number = binding_number
    ans.set_number = set_number
    ans.buffers = slice.clone([]resource.GenericResource{resource.to_generic_buffer(b)})
    return ans
}

make_input_binding_array :: proc(binding_number : u32, set_number : u32, bs : []$T) -> InputBinding
{
    ans := InputBinding{}
    ans.binding_number = binding_number
    ans.set_number = set_number
    ans.buffers = make([]resource.GenericResource, len(bs))
    for i in 0..<len(bs)
    {
        ans.buffers[i] = resource.to_generic_buffer(bs[i])
    }
    return ans
}

DescriptorSetContext :: struct
{
    descriptor_set : vk.DescriptorSet,
    pool : vk.DescriptorPool,
    bindings : []shader_module.BindingItem
}

allocate_descriptor_set :: proc(
    device_context : ^device.DeviceContext,
    shader_group : ^shader_group.ShaderGroupContext,
    set_index : u32
) -> DescriptorSetContext
{
    assert(shader_group.set_pools[set_index].n_remaining_sets > 0)

    ans := DescriptorSetContext{}
    ans.pool = shader_group.set_pools[set_index].pool

    first_binding_item_in_set := ~u32(0)
    last_binding_item_in_set := u32(0)
    for i in 0..<len(shader_group.bindings_items_sorted)
    {
        if shader_group.bindings_items_sorted[i].set_number == set_index
        {
            first_binding_item_in_set = math.min(u32(i), first_binding_item_in_set)
            last_binding_item_in_set = math.max(u32(i), last_binding_item_in_set)
        }
    }
    ans.bindings = shader_group.bindings_items_sorted[first_binding_item_in_set:(last_binding_item_in_set + 1)]

    descriptor_set_alloc_info := vk.DescriptorSetAllocateInfo{}
    descriptor_set_alloc_info.sType = vk.StructureType.DESCRIPTOR_SET_ALLOCATE_INFO
    descriptor_set_alloc_info.descriptorPool = shader_group.set_pools[set_index].pool
    descriptor_set_alloc_info.descriptorSetCount = 1
    descriptor_set_alloc_info.pSetLayouts = &shader_group.set_layouts[set_index]

    maybe_variable_length_bindings_at_end : Maybe(shader_module.BindingItem) = nil
    for bi in ans.bindings
    {
        if bi.variable_sized
        {
            maybe_variable_length_bindings_at_end = bi
        }
    }

    counts : u32
    set_counts : vk.DescriptorSetVariableDescriptorCountAllocateInfo
    if maybe_variable_length_bindings_at_end != nil
    {
        counts = maybe_variable_length_bindings_at_end.(shader_module.BindingItem).n_items_in_array
        set_counts.sType = vk.StructureType.DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO
        set_counts.descriptorSetCount = 1
        set_counts.pDescriptorCounts = &counts
        descriptor_set_alloc_info.pNext = &set_counts
    }

    assert(vk.AllocateDescriptorSets(
            device_context.device, &descriptor_set_alloc_info, &ans.descriptor_set
        ) == vk.Result.SUCCESS,
        "failed to create descriptor sets"
    )
    shader_group.set_pools[set_index].n_remaining_sets -= 1


    return ans
}

InputBinding :: struct
{
    binding_number : u32,
    set_number : u32,
    buffers : []resource.GenericResource
}

validate_descriptor_set_update :: proc(
    device_context : ^device.DeviceContext,
    descriptor_set : DescriptorSetContext,
    input_bindings : []InputBinding
)
{
    assert(len(descriptor_set.bindings) == len(input_bindings))
    for i in 0..<len(input_bindings)
    {
        if descriptor_set.bindings[i].binding_number != input_bindings[i].binding_number ||
            descriptor_set.bindings[i].set_number != input_bindings[i].set_number
        {
            fmt.panicf("set = %i binding = %i in descriptor set but input binding is set = %i binding = %i",
                descriptor_set.bindings[i].set_number,
                descriptor_set.bindings[i].binding_number,
                input_bindings[i].set_number,
                input_bindings[i].binding_number
            )
        }
        for b in input_bindings[i].buffers
        {
            switch v in b
            {
                case resource.GenericStorageBuffer:
                {
                    if shader_module.slang_type_to_vk_descriptor_type(
                        descriptor_set.bindings[i].slang_type
                    ) != vk.DescriptorType.STORAGE_BUFFER
                    {
                        fmt.panicf("set = %i binding = %i type mismatch",
                            descriptor_set.bindings[i].set_number,
                            descriptor_set.bindings[i].binding_number
                        )
                    }
                }
                case resource.GenericUniformBuffer:
                {
                    if shader_module.slang_type_to_vk_descriptor_type(
                        descriptor_set.bindings[i].slang_type
                    ) != vk.DescriptorType.UNIFORM_BUFFER
                    {
                        fmt.panicf("set = %i binding = %i type mismatch",
                            descriptor_set.bindings[i].set_number,
                            descriptor_set.bindings[i].binding_number
                        )
                    }
                }
                case resource.GenericBufferImage:
                {
                    if !(vk.ImageUsageFlag.STORAGE in v.usage) &&
                        shader_module.slang_type_to_vk_descriptor_type(
                            descriptor_set.bindings[i].slang_type
                        ) == vk.DescriptorType.STORAGE_IMAGE
                    {
                        fmt.panicf("set = %i binding = %i type mismatch",
                            descriptor_set.bindings[i].set_number,
                            descriptor_set.bindings[i].binding_number
                        )
                    }
                    if !(vk.ImageUsageFlag.SAMPLED in v.usage) &&
                        shader_module.slang_type_to_vk_descriptor_type(
                            descriptor_set.bindings[i].slang_type
                        ) == vk.DescriptorType.SAMPLED_IMAGE
                    {
                        fmt.panicf("set = %i binding = %i type mismatch",
                            descriptor_set.bindings[i].set_number,
                            descriptor_set.bindings[i].binding_number
                        )
                    }
                }
                case resource.GenericSampler:
                {
                    if shader_module.slang_type_to_vk_descriptor_type(
                            descriptor_set.bindings[i].slang_type
                        ) != vk.DescriptorType.SAMPLER
                    {
                        fmt.panicf("set = %i binding = %i type mismatch",
                            descriptor_set.bindings[i].set_number,
                            descriptor_set.bindings[i].binding_number
                        )
                    }
                }
                case resource.GenericAccelerationStructure:
                {
                    if shader_module.slang_type_to_vk_descriptor_type(
                            descriptor_set.bindings[i].slang_type
                        ) != vk.DescriptorType.ACCELERATION_STRUCTURE_KHR
                    {
                        fmt.panicf("set = %i binding = %i type mismatch",
                            descriptor_set.bindings[i].set_number,
                            descriptor_set.bindings[i].binding_number
                        )
                    }
                }
            }
        }
    }
}

update_descriptor_set :: proc(
    device_context : ^device.DeviceContext,
    descriptor_set : DescriptorSetContext,
    input_bindings : []InputBinding
)
{
    validate_descriptor_set_update(
        device_context,
        descriptor_set,
        input_bindings
    )

    descripter_writes := make([dynamic]vk.WriteDescriptorSet, 0, len(input_bindings))
    descripter_writes_acceleration_structures := make([dynamic]vk.WriteDescriptorSetAccelerationStructureKHR, 0, len(input_bindings))
    buffer_infos := make([dynamic]vk.DescriptorBufferInfo, 0, len(input_bindings))
    image_infos := make([dynamic]vk.DescriptorImageInfo, 0, len(input_bindings))
    acceleration_structures := make([dynamic]vk.AccelerationStructureKHR, 0, len(input_bindings))
    defer delete(descripter_writes)
    defer delete(buffer_infos)
    defer delete(image_infos)
    defer delete(acceleration_structures)
    defer delete(descripter_writes_acceleration_structures)

    for i in 0..<len(input_bindings)
    {
        if len(input_bindings[i].buffers) == 0 { continue }
        switch v in input_bindings[i].buffers[0]
        {
            case resource.GenericStorageBuffer:
            {
                for b in input_bindings[i].buffers
                {
                    buffer_info := vk.DescriptorBufferInfo{};
                    buffer_info.buffer = b.(resource.GenericStorageBuffer).buffer;
                    buffer_info.offset = 0;
                    buffer_info.range = b.(resource.GenericStorageBuffer).buffer_size;
                    append(&buffer_infos, buffer_info)
                }

                descripter_write := vk.WriteDescriptorSet{}
                descripter_write.sType = vk.StructureType.WRITE_DESCRIPTOR_SET
                descripter_write.dstSet = descriptor_set.descriptor_set
                descripter_write.dstBinding = input_bindings[i].binding_number
                descripter_write.dstArrayElement = 0
                descripter_write.descriptorType = shader_module.slang_type_to_vk_descriptor_type(
                    descriptor_set.bindings[i].slang_type
                )
                descripter_write.descriptorCount = u32(len(input_bindings[i].buffers))
                descripter_write.pBufferInfo = raw_data(buffer_infos[(len(buffer_infos) - len(input_bindings[i].buffers)):len(buffer_infos)])

                append(&descripter_writes, descripter_write)
            }
            case resource.GenericUniformBuffer:
            {
                for b in input_bindings[i].buffers
                {
                    buffer_info := vk.DescriptorBufferInfo{};
                    buffer_info.buffer = b.(resource.GenericUniformBuffer).buffer;
                    buffer_info.offset = 0;
                    buffer_info.range = b.(resource.GenericUniformBuffer).buffer_size;
                    append(&buffer_infos, buffer_info)
                }

                descripter_write := vk.WriteDescriptorSet{}
                descripter_write.sType = vk.StructureType.WRITE_DESCRIPTOR_SET
                descripter_write.dstSet = descriptor_set.descriptor_set
                descripter_write.dstBinding = input_bindings[i].binding_number
                descripter_write.dstArrayElement = 0
                descripter_write.descriptorType = shader_module.slang_type_to_vk_descriptor_type(
                    descriptor_set.bindings[i].slang_type
                )
                descripter_write.descriptorCount = u32(len(input_bindings[i].buffers))
                descripter_write.pBufferInfo = raw_data(buffer_infos[(len(buffer_infos) - len(input_bindings[i].buffers)):len(buffer_infos)])

                append(&descripter_writes, descripter_write)
            }
            case resource.GenericBufferImage:
            {
                for b in input_bindings[i].buffers
                {
                    image_info := vk.DescriptorImageInfo{}
                    image_info.imageView = b.(resource.GenericBufferImage).image_view
                    image_info.imageLayout = b.(resource.GenericBufferImage).layout
                    append(&image_infos, image_info)
                }

                descripter_write := vk.WriteDescriptorSet{}
                descripter_write.sType = vk.StructureType.WRITE_DESCRIPTOR_SET
                descripter_write.dstSet = descriptor_set.descriptor_set
                descripter_write.dstBinding = input_bindings[i].binding_number
                descripter_write.dstArrayElement = 0
                descripter_write.descriptorType = shader_module.slang_type_to_vk_descriptor_type(
                    descriptor_set.bindings[i].slang_type
                )
                descripter_write.descriptorCount = u32(len(input_bindings[i].buffers))
                descripter_write.pImageInfo = raw_data(image_infos[(len(image_infos) - len(input_bindings[i].buffers)):len(image_infos)])

                append(&descripter_writes, descripter_write)
            }
            case resource.GenericSampler:
            {
                for b in input_bindings[i].buffers
                {
                    image_info := vk.DescriptorImageInfo{}
                    image_info.sampler = b.(resource.GenericSampler).sampler
                    append(&image_infos, image_info)
                }

                descripter_write := vk.WriteDescriptorSet{}
                descripter_write.sType = vk.StructureType.WRITE_DESCRIPTOR_SET
                descripter_write.dstSet = descriptor_set.descriptor_set
                descripter_write.dstBinding = input_bindings[i].binding_number
                descripter_write.dstArrayElement = 0
                descripter_write.descriptorType = shader_module.slang_type_to_vk_descriptor_type(
                    descriptor_set.bindings[i].slang_type
                )
                descripter_write.descriptorCount = u32(len(input_bindings[i].buffers))
                descripter_write.pImageInfo = raw_data(image_infos[(len(image_infos) - len(input_bindings[i].buffers)):len(image_infos)])

                append(&descripter_writes, descripter_write)
            }
            case resource.GenericAccelerationStructure:
            {
                for b in input_bindings[i].buffers
                {
                    append(&acceleration_structures, b.(resource.GenericAccelerationStructure).acceleration_structure)
                }

                descripter_acceleration_write := vk.WriteDescriptorSetAccelerationStructureKHR{}
                descripter_acceleration_write.sType = vk.StructureType.WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR
                descripter_acceleration_write.accelerationStructureCount = 1
                descripter_acceleration_write.pAccelerationStructures = raw_data(acceleration_structures[(len(acceleration_structures) - len(input_bindings[i].buffers)):len(acceleration_structures)])

                append(&descripter_writes_acceleration_structures, descripter_acceleration_write)

                descripter_write := vk.WriteDescriptorSet{}
                descripter_write.sType = vk.StructureType.WRITE_DESCRIPTOR_SET
                descripter_write.dstSet = descriptor_set.descriptor_set
                descripter_write.dstBinding = input_bindings[i].binding_number
                descripter_write.dstArrayElement = 0
                descripter_write.descriptorType = shader_module.slang_type_to_vk_descriptor_type(
                    descriptor_set.bindings[i].slang_type
                )
                descripter_write.descriptorCount = u32(len(input_bindings[i].buffers))
                descripter_write.pNext = &descripter_writes_acceleration_structures[len(descripter_writes_acceleration_structures) - 1]

                append(&descripter_writes, descripter_write)
            }
        }
    }

    vk.UpdateDescriptorSets(
        device_context.device,
        u32(len(descripter_writes)), raw_data(descripter_writes),
        0, nil
    )
}
