package shader_module
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

// represents everything required to interact with a shader
ShaderModuleContext :: struct
{
    vk_shader_module: vk.ShaderModule,
    binding_items : []BindingItem,
    type : ShaderType
}

ShaderType :: enum
{
    COMPUTE,
    VERTEX,
    FRAGMENT
}

create_shader_module :: proc(
    device_context : ^device.DeviceContext,
    shader_path_slang : string, shader_path_spirv : string,
    type : ShaderType,
    variable_length_array_max_size : u32 = 1
) -> ShaderModuleContext
{
    compute_shader_code_slang, compute_shader_read_success_slang := os.read_entire_file(
        shader_path_slang,
        context.temp_allocator,
    )
    assert(compute_shader_read_success_slang, "cannot read slang file for compute pipeline")
    compute_shader_code_slang_string := string(compute_shader_code_slang)

    compute_shader_spirv, compute_shader_read_success_spirv := os.read_entire_file(
        shader_path_spirv,
        context.temp_allocator,
    )
    assert(compute_shader_read_success_spirv, "cannot read spirv file for compute pipeline")

    ans := ShaderModuleContext{}
    ans.binding_items = parse_slang_file_to_binding_items(
        compute_shader_code_slang_string,
        variable_length_array_max_size
    )
    ans.type = type

    compute_shader_module_info := vk.ShaderModuleCreateInfo{}
    compute_shader_module_info.sType = vk.StructureType.SHADER_MODULE_CREATE_INFO
    compute_shader_module_info.codeSize = len(compute_shader_spirv)
    compute_shader_module_info.pCode = cast(^u32)raw_data(compute_shader_spirv)

    assert(
        vk.CreateShaderModule(
           device_context.device,
           &compute_shader_module_info,
           nil,
           &ans.vk_shader_module,
       ) == vk.Result.SUCCESS
    )

    return ans
}

delete_shader_module :: proc(device_context : ^device.DeviceContext, shader_module : ShaderModuleContext)
{
    vk.DestroyShaderModule(
        device_context.device,
        shader_module.vk_shader_module,
        nil
    )
}
