package pipeline
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
import "../descriptor_set"
import sa "core:container/small_array"

ComputePipelineContext :: struct
{
    shader_group: shader_group.ShaderGroupContext,
    pipeline_layout : vk.PipelineLayout,
    pipeline : vk.Pipeline,
}

create_compute_pipeline :: proc(
    device_context : ^device.DeviceContext,
    shader_group : shader_group.ShaderGroupContext
) -> ComputePipelineContext
{
    assert(len(shader_group.shader_modules) == 1)
    assert(shader_group.shader_modules[0].type == .COMPUTE)

    ans := ComputePipelineContext{}
    ans.shader_group = shader_group

    // make pipeline layout
    pipeline_layout_info := vk.PipelineLayoutCreateInfo{};
    pipeline_layout_info.sType = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO;
    pipeline_layout_info.setLayoutCount = u32(len(shader_group.set_layouts))
    pipeline_layout_info.pSetLayouts = raw_data(shader_group.set_layouts)

    assert(
        vk.CreatePipelineLayout(
            device_context.device,
            &pipeline_layout_info,
            nil,
            &ans.pipeline_layout
        ) == vk.Result.SUCCESS
    )

    // make pipeline
    compute_shader_stage_info := vk.PipelineShaderStageCreateInfo{}
    compute_shader_stage_info.sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO;
    compute_shader_stage_info.stage = {vk.ShaderStageFlag.COMPUTE};
    compute_shader_stage_info.module = shader_group.shader_modules[0].vk_shader_module;
    compute_shader_stage_info.pName = "main";

    pipeline_info := vk.ComputePipelineCreateInfo{}
    pipeline_info.sType = vk.StructureType.COMPUTE_PIPELINE_CREATE_INFO;
    pipeline_info.layout = ans.pipeline_layout;
    pipeline_info.stage = compute_shader_stage_info;

    assert(
        vk.CreateComputePipelines(
            device_context.device,
            0,
            1,
            &pipeline_info,
            nil,
            &ans.pipeline
        ) == vk.Result.SUCCESS
    )

    return ans
}

delete_compute_pipeline :: proc(device_context : ^device.DeviceContext, compute_pipeline : ComputePipelineContext)
{
    vk.DestroyPipeline(
        device_context.device,
        compute_pipeline.pipeline,
        nil
    )
    vk.DestroyPipelineLayout(
        device_context.device,
        compute_pipeline.pipeline_layout,
        nil
    )
}

invoke_compute_pipeline :: proc(
    device_context : ^device.DeviceContext,
    compute_pipeline : ^ComputePipelineContext,
    descriptor_sets : []descriptor_set.DescriptorSetContext,
    invokation_counts : [3]u32
)
{
    assert(len(compute_pipeline.shader_group.set_layouts) == len(descriptor_sets))

    vk_descriptor_sets : sa.Small_Array(8, vk.DescriptorSet)
    for ds in descriptor_sets
    {
        sa.append(&vk_descriptor_sets, ds.descriptor_set)
    }

    run_compute_pipeline_and_wait(
        device_context,
        sa.slice(&vk_descriptor_sets),
        compute_pipeline^,
        invokation_counts.x, invokation_counts.y, invokation_counts.z,
    )
}

run_compute_pipeline_and_wait :: proc(
    device_context : ^device.DeviceContext,
    descriptor_sets : []vk.DescriptorSet,
    pipeline : ComputePipelineContext,
    x_count : u32, y_count : u32, z_count : u32
)
{
    st := time.now()._nsec

    vk.ResetCommandBuffer(device_context.command_buffer.command_buffer, {})

    write_compute_command_buffer(
        device_context,
        descriptor_sets,
        pipeline,
        x_count, y_count, z_count
    )

    submit_info := vk.SubmitInfo{}
    submit_info.sType = vk.StructureType.SUBMIT_INFO
    submit_info.commandBufferCount = 1
    command_buffer_copy := device_context
    submit_info.pCommandBuffers = &command_buffer_copy.command_buffer.command_buffer

    assert(
        vk.QueueSubmit(
            device_context.graphics_queue,
            1,
            &submit_info,
            0
        ) == vk.Result.SUCCESS
    )

    // wait for the shader we should use semaphorse here in the future
    vk.QueueWaitIdle(device_context.graphics_queue)
}

write_compute_command_buffer :: proc(
    device_context : ^device.DeviceContext,
    descriptor_sets : []vk.DescriptorSet,
    pipeline : ComputePipelineContext,
    x_count : u32, y_count : u32, z_count : u32
    )
{
    begin_info := vk.CommandBufferBeginInfo{}
    begin_info.sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO

    assert(
        vk.BeginCommandBuffer(
            device_context.command_buffer.command_buffer,
            &begin_info
        ) == vk.Result.SUCCESS
    )

    descriptor_sets_copy := descriptor_sets

    vk.CmdBindPipeline(device_context.command_buffer.command_buffer, vk.PipelineBindPoint.COMPUTE, pipeline.pipeline)
    vk.CmdBindDescriptorSets(
        device_context.command_buffer.command_buffer,
        vk.PipelineBindPoint.COMPUTE,
        pipeline.pipeline_layout,
        0,
        u32(len(descriptor_sets_copy)),
        raw_data(descriptor_sets_copy),
        0,
        nil
    )
    vk.CmdDispatch(device_context.command_buffer.command_buffer, x_count, y_count, z_count)

    assert(
        vk.EndCommandBuffer(
            device_context.command_buffer.command_buffer
        ) == vk.Result.SUCCESS
    )
}
