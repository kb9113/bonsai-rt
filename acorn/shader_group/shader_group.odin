package shader_group
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:log"
import "core:math"
import "core:slice"
import "core:time"
import "../resource"
import "../device"
import "../shader_module"
import "core:c/libc"
import sa "core:container/small_array"


DescriptorPoolContext :: struct
{
    n_remaining_sets : u32,
    pool : vk.DescriptorPool
}

ShaderGroupContext :: struct
{
    shader_modules : []shader_module.ShaderModuleContext,
    bindings_items_sorted : []shader_module.BindingItem,
    // expect number of theses equal to the largest set index in the shader modules + 1
    set_layouts : []vk.DescriptorSetLayout,
    set_pools : []DescriptorPoolContext,
}

make_shader_group :: proc(
    device_context : ^device.DeviceContext,
    shader_modules : []shader_module.ShaderModuleContext,
    max_number_of_sets : u32
) -> ShaderGroupContext
{
    for i in 0..<(len(shader_modules) - 1)
    {
        assert(
            slice.equal(shader_modules[i].binding_items, shader_modules[i + 1].binding_items),
            "missmatch in bindings between shader modules"
        )
    }

    // calculate stage flags
    stage_flags : vk.ShaderStageFlags
    for sm in shader_modules
    {
        switch sm.type
        {
            case .VERTEX: stage_flags |= {vk.ShaderStageFlag.VERTEX}
            case .FRAGMENT: stage_flags |= {vk.ShaderStageFlag.FRAGMENT}
            case .COMPUTE: stage_flags |= {vk.ShaderStageFlag.COMPUTE}
        }
    }

    ans := ShaderGroupContext{}
    ans.shader_modules = slice.clone(shader_modules)
    ans.bindings_items_sorted = slice.clone(shader_modules[0].binding_items)
    ans.set_layouts = make_descriptor_layouts(
        device_context,
        shader_modules[0].binding_items,
        stage_flags
    )
    ans.set_pools = make_desciptor_pool(
        device_context,
        shader_modules[0].binding_items,
        max_number_of_sets
    )

    input_binding_less :: proc(l : shader_module.BindingItem, r : shader_module.BindingItem) -> bool
    {
        if l.set_number < r.set_number { return true }
        if l.set_number > r.set_number { return false }
        return l.binding_number < r.binding_number
    }
    slice.sort_by(ans.bindings_items_sorted, input_binding_less)

    return ans
}

delete_shader_group :: proc(device_context : ^device.DeviceContext, shader_group : ShaderGroupContext)
{
    for pool in shader_group.set_pools
    {
        vk.DestroyDescriptorPool(
            device_context.device,
            pool.pool,
            nil
        )
    }
    for layout in shader_group.set_layouts
    {
        vk.DestroyDescriptorSetLayout(
            device_context.device,
            layout,
            nil
        )
    }
}

// makes layouts for the given shader modules
// this validates than no module uses a bindigns item the missmatches with another
make_descriptor_layouts :: proc(
    device_context : ^device.DeviceContext,
    binding_items : []shader_module.BindingItem,
    stage_flags : vk.ShaderStageFlags
) -> []vk.DescriptorSetLayout
{
    // setup bindings
    if len(binding_items) == 0
    {
        return []vk.DescriptorSetLayout{}
    }
    // need min set index as well I think
    max_set_index : u32 = 0
    for bi in binding_items
    {
        max_set_index = math.max(max_set_index, bi.set_number)
    }

    set_index_to_vk_binding_layouts := make([][dynamic]vk.DescriptorSetLayoutBinding, max_set_index + 1)
    set_index_to_vk_binding_flags := make([][dynamic]vk.DescriptorBindingFlags, max_set_index + 1)

    for bi in binding_items
    {
        descriptor_layout_info := vk.DescriptorSetLayoutBinding{}
        descriptor_layout_info.binding = bi.binding_number
        descriptor_layout_info.descriptorType = shader_module.slang_type_to_vk_descriptor_type(bi.slang_type)
        descriptor_layout_info.descriptorCount = bi.n_items_in_array
        descriptor_layout_info.stageFlags = stage_flags
        append(&set_index_to_vk_binding_layouts[bi.set_number], descriptor_layout_info)


        binding_flags := vk.DescriptorBindingFlags{}
        if bi.variable_sized
        {
            binding_flags |= {
                vk.DescriptorBindingFlag.VARIABLE_DESCRIPTOR_COUNT,
                vk.DescriptorBindingFlag.PARTIALLY_BOUND
            }
        }

        append(&set_index_to_vk_binding_flags[bi.set_number], binding_flags)
    }

    set_layouts := make([dynamic]vk.DescriptorSetLayout)
    for i in 0..=max_set_index
    {
        binding_flags := vk.DescriptorSetLayoutBindingFlagsCreateInfo{}
        binding_flags.sType = vk.StructureType.DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO
        binding_flags.bindingCount = u32(len(set_index_to_vk_binding_flags[i]))
        binding_flags.pBindingFlags = raw_data(set_index_to_vk_binding_flags[i])

        layout_create_info := vk.DescriptorSetLayoutCreateInfo{}
        layout_create_info.sType = vk.StructureType.DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layout_create_info.bindingCount = u32(len(set_index_to_vk_binding_layouts[i]))
        layout_create_info.pBindings = raw_data(set_index_to_vk_binding_layouts[i])
        layout_create_info.pNext = &binding_flags

        layout : vk.DescriptorSetLayout
        assert(vk.CreateDescriptorSetLayout(
               device_context.device,
               &layout_create_info,
               nil,
               &layout,
            ) == vk.Result.SUCCESS,
            "failed to create descriptor set"
        )
        append(&set_layouts, layout)
        delete(set_index_to_vk_binding_layouts[i])
        delete(set_index_to_vk_binding_flags[i])
    }

    delete(set_index_to_vk_binding_layouts)
    delete(set_index_to_vk_binding_flags)

    return set_layouts[:]
}

make_desciptor_pool :: proc(
    device_context : ^device.DeviceContext,
    binding_items : []shader_module.BindingItem,
    max_number_of_sets : u32
) -> []DescriptorPoolContext
{
    // setup bindings
    if len(binding_items) == 0
    {
        return []DescriptorPoolContext{}
    }
    // need min set index as well I think
    max_set_index : u32 = 0
    for bi in binding_items
    {
        max_set_index = math.max(max_set_index, bi.set_number)
    }

    set_index_to_vk_descriptor_pool_sizes := make([][dynamic]vk.DescriptorPoolSize, max_set_index + 1)

    for bi in binding_items
    {
        pool_size := vk.DescriptorPoolSize{}
        pool_size.type = shader_module.slang_type_to_vk_descriptor_type(bi.slang_type)
        pool_size.descriptorCount = max_number_of_sets

        append(&set_index_to_vk_descriptor_pool_sizes[bi.set_number], pool_size)
    }

    set_pools := make([dynamic]DescriptorPoolContext)
    for i in 0..=max_set_index
    {
        descriptor_pool_create_info := vk.DescriptorPoolCreateInfo{}
        descriptor_pool_create_info.sType = vk.StructureType.DESCRIPTOR_POOL_CREATE_INFO
        descriptor_pool_create_info.poolSizeCount = u32(len(set_index_to_vk_descriptor_pool_sizes[i]))
        descriptor_pool_create_info.pPoolSizes = raw_data(set_index_to_vk_descriptor_pool_sizes[i])
        descriptor_pool_create_info.maxSets = max_number_of_sets

        pool_context := DescriptorPoolContext{}
        pool_context.n_remaining_sets = max_number_of_sets
        assert(vk.CreateDescriptorPool(
                device_context.device, &descriptor_pool_create_info, nil, &pool_context.pool
            ) == vk.Result.SUCCESS,
            "failed to create descriptor pool"
        )
        append(&set_pools, pool_context)
        delete(set_index_to_vk_descriptor_pool_sizes[i])
    }
    delete(set_index_to_vk_descriptor_pool_sizes)

    return set_pools[:]
}
