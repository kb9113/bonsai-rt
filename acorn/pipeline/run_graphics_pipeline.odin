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
import "core:c/libc"
import sa "core:container/small_array"
import "../shader_group"
import "../descriptor_set"

DrawCmd :: struct
{
    index_count : u32,
    instance_count : u32,
    first_index : u32,
    first_vertex : u32,
    first_instance : u32
}

run_graphics_pipeline_and_wait :: proc(
    device_context : ^device.DeviceContext,
    pipeline : ^GraphicsPipelineContext,
    index_buffer : resource.GenericResource,
    vertex_buffers : []resource.GenericResource,
    instance_buffers : []resource.GenericResource,
    descriptor_sets : []vk.DescriptorSet,
    draw_cmds : []DrawCmd,
    frame_buffer_context : FrameBufferContext
)
{
    begin_info := vk.CommandBufferBeginInfo{}
    begin_info.sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO
    begin_info.flags = {}
    assert(
        vk.BeginCommandBuffer(
            device_context.command_buffer.command_buffer,
            &begin_info
        ) == vk.Result.SUCCESS
    )

    render_pass_begin_info := vk.RenderPassBeginInfo{}
    render_pass_begin_info.sType = vk.StructureType.RENDER_PASS_BEGIN_INFO
    render_pass_begin_info.renderPass = pipeline.render_pass
    render_pass_begin_info.framebuffer = frame_buffer_context.frame_buffer

    render_pass_begin_info.renderArea.offset = vk.Offset2D{0, 0}
    render_pass_begin_info.renderArea.extent = vk.Extent2D{frame_buffer_context.width, frame_buffer_context.height}

    clear_values : sa.Small_Array(2, vk.ClearValue)
    for attachemnt_config in pipeline.attachment_configs
    {
        if attachemnt_config.type == .Color
        {
            cv := vk.ClearValue{}
            cv.color.float32 = [4]f32{0, 0, 0, 0}
            sa.append(&clear_values, cv)
        }
        if attachemnt_config.type == .Depth
        {
            cv := vk.ClearValue{}
            cv.depthStencil.depth = 1
            cv.depthStencil.stencil = 0
            sa.append(&clear_values, cv)
        }
    }

    render_pass_begin_info.clearValueCount = u32(sa.len(clear_values))
    render_pass_begin_info.pClearValues = raw_data(sa.slice(&clear_values))

    vk.CmdBeginRenderPass(
        device_context.command_buffer.command_buffer,
        &render_pass_begin_info,
        vk.SubpassContents.INLINE
    )

    vk.CmdBindPipeline(
        device_context.command_buffer.command_buffer,
        vk.PipelineBindPoint.GRAPHICS,
        pipeline.pipeline
    )

    vk.CmdBindDescriptorSets(
        device_context.command_buffer.command_buffer,
        vk.PipelineBindPoint.GRAPHICS,
        pipeline.pipeline_layout,
        0,
        u32(len(descriptor_sets)),
        raw_data(descriptor_sets),
        0,
        nil
    )

    vk.CmdBindIndexBuffer(
        device_context.command_buffer.command_buffer,
        resource.generic_buffer_vk_buffer(index_buffer), 0, vk.IndexType.UINT32
    )

    for i in 0..<len(vertex_buffers)
    {
        vk_vertex_buffer := resource.generic_buffer_vk_buffer(vertex_buffers[i])
        vk_vertex_offset := vk.DeviceSize(0)
        vk.CmdBindVertexBuffers(
            device_context.command_buffer.command_buffer,
            u32(i), 1, &vk_vertex_buffer, &vk_vertex_offset
        )
    }

    for i in 0..<len(instance_buffers)
    {
        vk_instance_buffer := resource.generic_buffer_vk_buffer(instance_buffers[i])
        vk_instance_offset := vk.DeviceSize(0)
        vk.CmdBindVertexBuffers(
            device_context.command_buffer.command_buffer,
            u32(i + len(vertex_buffers)), 1, &vk_instance_buffer, &vk_instance_offset
        )
    }

    viewport := vk.Viewport{}
    viewport.x = 0
    viewport.y = 0
    viewport.width = f32(frame_buffer_context.width)
    viewport.height = f32(frame_buffer_context.height)
    viewport.minDepth = 0
    viewport.maxDepth = 1
    vk.CmdSetViewport(device_context.command_buffer.command_buffer, 0, 1, &viewport);

    scissor := vk.Rect2D{}
    scissor.offset = vk.Offset2D{0, 0}
    scissor.extent = vk.Extent2D{frame_buffer_context.width, frame_buffer_context.height}
    vk.CmdSetScissor(device_context.command_buffer.command_buffer, 0, 1, &scissor)

    for draw_cmd in draw_cmds
    {
        vk.CmdDrawIndexed(
            device_context.command_buffer.command_buffer,
            draw_cmd.index_count, draw_cmd.instance_count,
            draw_cmd.first_index, i32(draw_cmd.first_vertex), draw_cmd.first_instance
        )
    }

    vk.CmdEndRenderPass(device_context.command_buffer.command_buffer)

    assert(
        vk.EndCommandBuffer(device_context.command_buffer.command_buffer) == vk.Result.SUCCESS
    )
}

invoke_graphics_pipeline :: proc(
    device_context : ^device.DeviceContext,
    pipeline : ^GraphicsPipelineContext,
    index_buffer : resource.GenericResource,
    vertex_buffers : []resource.GenericResource,
    instance_buffers : []resource.GenericResource,
    descriptor_sets : []descriptor_set.DescriptorSetContext,
    draw_cmds : []DrawCmd,
    frame_buffer : FrameBufferContext,
    wait_semaphores : []vk.Semaphore
) -> vk.Semaphore
{
    vk_descriptor_sets : sa.Small_Array(8, vk.DescriptorSet)
    for ds in descriptor_sets
    {
        sa.append(&vk_descriptor_sets, ds.descriptor_set)
    }

    // draw and submit on the gpu
    vk.ResetCommandBuffer(device_context.command_buffer.command_buffer, {})

    assert(frame_buffer.linked_render_pass == pipeline.render_pass)
    run_graphics_pipeline_and_wait(
        device_context,
        pipeline,
        index_buffer,
        vertex_buffers,
        instance_buffers,
        sa.slice(&vk_descriptor_sets),
        draw_cmds,
        frame_buffer
    )

    submit_info := vk.SubmitInfo{}
    submit_info.sType = vk.StructureType.SUBMIT_INFO

    wait_semaphores_copy := wait_semaphores
    wait_stages := []vk.PipelineStageFlags{{vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT}}
    submit_info.waitSemaphoreCount = u32(len(wait_semaphores_copy))
    submit_info.pWaitSemaphores = raw_data(wait_semaphores_copy)
    submit_info.pWaitDstStageMask = raw_data(wait_stages)

    submit_info.commandBufferCount = 1
    submit_info.pCommandBuffers = &device_context.command_buffer.command_buffer

    signal_semaphores := []vk.Semaphore{
        pipeline.render_finished_semaphore
    }
    submit_info.signalSemaphoreCount = 1
    submit_info.pSignalSemaphores = raw_data(signal_semaphores)

    assert(
        vk.QueueSubmit(device_context.graphics_queue, 1, &submit_info, 0) == vk.Result.SUCCESS
    )

    return pipeline.render_finished_semaphore
}
