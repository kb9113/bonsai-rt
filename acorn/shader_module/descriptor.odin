package shader_module
import vk "vendor:vulkan"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:log"
import "core:math"
import "core:slice"
import "core:time"
import "../scan"
import "../resource"
import "../device"

SLANGBindingType :: enum
{
    ConstantBuffer,
    RWStructuredBuffer,
    StructuredBuffer,
    RWTexture2D,
    Texture2D,
    RWTexture2DSampled,
    Texture2DSampled,
    SamplerState,
    RayAccelerationStructure
}

BindingItem :: struct
{
    binding_number : u32,
    set_number : u32,
    slang_type : SLANGBindingType,
    n_items_in_array : u32,
    variable_sized : bool
}

slang_type_to_vk_descriptor_type :: proc(slang_type : SLANGBindingType) -> vk.DescriptorType
{
    switch slang_type
    {
        case .ConstantBuffer: return vk.DescriptorType.UNIFORM_BUFFER
        case .RWStructuredBuffer: return vk.DescriptorType.STORAGE_BUFFER
        case .StructuredBuffer: return vk.DescriptorType.STORAGE_BUFFER
        case .RWTexture2D: return vk.DescriptorType.STORAGE_IMAGE
        case .Texture2D: return vk.DescriptorType.STORAGE_IMAGE
        case .RWTexture2DSampled: return vk.DescriptorType.SAMPLED_IMAGE
        case .Texture2DSampled: return vk.DescriptorType.SAMPLED_IMAGE
        case .SamplerState: return vk.DescriptorType.SAMPLER
        case .RayAccelerationStructure: return vk.DescriptorType.ACCELERATION_STRUCTURE_KHR
    }
    panic("this should never happen")
}

line_to_array_count :: proc(line : string) -> u32
{
    open_bracket_index := strings.index_rune(line, '[')
    close_bracket_index := strings.index_rune(line, ']')
    if open_bracket_index == -1 || close_bracket_index == -1
    {
        return 1;
    }
    array_count, ok := strconv.parse_u64(line[(open_bracket_index + 1):close_bracket_index])
    if !ok
    {
        return 1;
    }
    return u32(array_count)
}

parse_slang_file_to_binding_items :: proc(
    compute_shader_code_slang_string : string,
    variable_length_array_max_size : u32
) -> []BindingItem
{
    binding_items := make([dynamic]BindingItem)
    next_line_should_be_buffer_declarion : bool = false
    compute_shader_code_slang_string_copy := compute_shader_code_slang_string
    for line in strings.split_lines_iterator(&compute_shader_code_slang_string_copy)
    {
        if next_line_should_be_buffer_declarion
        {
            if strings.starts_with(line, "ConstantBuffer")
            {
                binding_items[len(binding_items) - 1].slang_type = .ConstantBuffer
            }
            else if strings.starts_with(line, "RWStructuredBuffer")
            {
                binding_items[len(binding_items) - 1].slang_type = .RWStructuredBuffer
            }
            else if strings.starts_with(line, "StructuredBuffer")
            {
                binding_items[len(binding_items) - 1].slang_type = .StructuredBuffer
            }
            else if strings.starts_with(line, "RWTexture2D") && strings.contains(line, "#Sampled")
            {
                binding_items[len(binding_items) - 1].slang_type = .RWTexture2DSampled
            }
            else if strings.starts_with(line, "Texture2D") && strings.contains(line, "#Sampled")
            {
                binding_items[len(binding_items) - 1].slang_type = .Texture2DSampled
            }
            else if strings.starts_with(line, "RWTexture2D")
            {
                binding_items[len(binding_items) - 1].slang_type = .RWTexture2D
            }
            else if strings.starts_with(line, "Texture2D")
            {
                binding_items[len(binding_items) - 1].slang_type = .Texture2D
            }
            else if strings.starts_with(line, "SamplerState")
            {
                binding_items[len(binding_items) - 1].slang_type = .SamplerState
            }
            else if strings.starts_with(line, "RaytracingAccelerationStructure")
            {
                binding_items[len(binding_items) - 1].slang_type = .RayAccelerationStructure
            }
            else
            {
                fmt.panicf("expected a buffer declariton but got: %s", line)
            }

            if strings.contains(line, "[]")
            {
                binding_items[len(binding_items) - 1].n_items_in_array = variable_length_array_max_size
                binding_items[len(binding_items) - 1].variable_sized = true
            }
            else
            {
                binding_items[len(binding_items) - 1].n_items_in_array = line_to_array_count(line)
                binding_items[len(binding_items) - 1].variable_sized = false
            }
            next_line_should_be_buffer_declarion = false
        }
        else if strings.starts_with(line, "[[vk::binding(")
        {
            binding_number : u32
            set_number : u32
            scan_ok := scan.scan(line, "[[vk::binding(", &binding_number, ", ", &set_number, ")]]")
            assert(scan_ok, "malformed binding in slang file")

            binding_item := BindingItem{}
            binding_item.binding_number = binding_number;
            binding_item.set_number = set_number

            next_line_should_be_buffer_declarion = true

            append(&binding_items, binding_item)
        }
    }

    input_binding_less :: proc(l : BindingItem, r : BindingItem) -> bool
    {
        if l.set_number < r.set_number { return true }
        if l.set_number > r.set_number { return false }
        return l.binding_number < r.binding_number
    }
    slice.sort_by(binding_items[:], input_binding_less)
    return binding_items[:]
}
