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
import "base:runtime"
import sa "core:container/small_array"
import "../shader_group"
import "../descriptor_set"

// frame buffers just groups the resources you are rendeing to togeather
// theses resources should match up with the attachments
FrameBufferContext :: struct
{
    linked_render_pass : vk.RenderPass,
    frame_buffer : vk.Framebuffer,
    width : u32,
    height : u32
}

AttachmentType :: enum{Color, Depth, Resolve}
Attachment :: struct
{
    type : AttachmentType,
    image : resource.ImageInfo
}

AttachmentConfig :: struct
{
    type : AttachmentType,
    format : vk.Format,
    sample_count : vk.SampleCountFlags
}

AttachmentTypeSet :: bit_set[AttachmentType]

create_frame_buffer :: proc(
    device_context : ^device.DeviceContext,
    graphics_pipeline : ^GraphicsPipelineContext,
    attachments : []Attachment
) -> FrameBufferContext
{
    ans := FrameBufferContext{}
    ans.linked_render_pass = graphics_pipeline.render_pass
    ans.width = u32(attachments[0].image.width)
    ans.height = u32(attachments[0].image.height)

    framebuffer_info := vk.FramebufferCreateInfo{}
    framebuffer_info.sType = vk.StructureType.FRAMEBUFFER_CREATE_INFO
    framebuffer_info.renderPass = graphics_pipeline.render_pass

    assert(len(graphics_pipeline.attachment_configs) == len(attachments))
    attachemnt_image_views := make([]vk.ImageView, len(attachments))
    defer delete(attachemnt_image_views)
    for i in 0..<len(attachments)
    {
        assert(graphics_pipeline.attachment_configs[i].type == attachments[i].type)
        assert(u32(attachments[i].image.width) == ans.width)
        assert(u32(attachments[i].image.height) == ans.height)
        attachemnt_image_views[i] = attachments[i].image.image_view
    }

    framebuffer_info.attachmentCount = u32(len(attachemnt_image_views))
    framebuffer_info.pAttachments = raw_data(attachemnt_image_views)
    framebuffer_info.width = ans.width
    framebuffer_info.height = ans.height
    framebuffer_info.layers = 1;

    assert(
        vk.CreateFramebuffer(
            device_context.device,
            &framebuffer_info,
            nil,
            &ans.frame_buffer
        ) == vk.Result.SUCCESS
    )
    return ans
}

GraphicsPipelineContext :: struct
{
    shader_group: shader_group.ShaderGroupContext,
    render_pass : vk.RenderPass,
    pipeline_layout : vk.PipelineLayout,
    pipeline : vk.Pipeline,
    render_finished_semaphore : vk.Semaphore,
    attachment_configs : []AttachmentConfig,
    vertex_types : []typeid,
    instance_types : []typeid
}

create_grahics_pipeline :: proc(
    device_context : ^device.DeviceContext,
    vertex_types : []typeid,
    instance_types : []typeid,
    shader_group : shader_group.ShaderGroupContext,
    attachment_configs : []AttachmentConfig,
    enable_multisampleing : bool,
    max_instances : u32 // number of unique binding combinaitons per set
) -> GraphicsPipelineContext
{
    render_pass := vk_create_render_pass(device_context, attachment_configs)

    pipeline_layout, pipeline := vk_create_graphics_pipeline(
        device_context,
        vertex_types,
        instance_types,
        render_pass,
        shader_group,
        enable_multisampleing,
        0
    )

    ans := GraphicsPipelineContext{}
    ans.vertex_types = slice.clone(vertex_types)
    ans.instance_types = slice.clone(instance_types)
    ans.attachment_configs = slice.clone(attachment_configs)
    ans.shader_group = shader_group
    ans.render_pass = render_pass
    ans.pipeline_layout = pipeline_layout
    ans.pipeline = pipeline
    ans.render_finished_semaphore = device.create_semaphore(device_context)
    return ans
}


// think we need a seperate pipeline for evey subpass
vk_create_render_pass :: proc(
    device_context : ^device.DeviceContext,
    attachment_configs : []AttachmentConfig
) -> vk.RenderPass
{
    attachments := make([dynamic]vk.AttachmentDescription)
    defer delete(attachments)
    attachment_refs := make([dynamic]vk.AttachmentReference)
    defer delete(attachment_refs)
    subpass := vk.SubpassDescription{}
    subpass.pipelineBindPoint = vk.PipelineBindPoint.GRAPHICS

    dependency := vk.SubpassDependency{}
    dependency.srcSubpass = vk.SUBPASS_EXTERNAL
    dependency.dstSubpass = 0

    dependency.srcStageMask = {}
    dependency.srcAccessMask = {}

    dependency.dstStageMask = {}
    dependency.dstAccessMask = {}

    for attachemnt in attachment_configs
    {
        switch attachemnt.type
        {
            case .Color:
            {
                color_attachment := vk.AttachmentDescription{}
                color_attachment.format = attachemnt.format
                color_attachment.samples = attachemnt.sample_count

                color_attachment.loadOp = vk.AttachmentLoadOp.CLEAR
                color_attachment.storeOp = vk.AttachmentStoreOp.STORE

                color_attachment.stencilLoadOp = vk.AttachmentLoadOp.DONT_CARE
                color_attachment.stencilStoreOp = vk.AttachmentStoreOp.DONT_CARE

                color_attachment.initialLayout = vk.ImageLayout.UNDEFINED
                color_attachment.finalLayout = vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL
                append(&attachments, color_attachment)

                color_attachment_ref := vk.AttachmentReference{}
                color_attachment_ref.attachment = u32(len(attachments) - 1)
                color_attachment_ref.layout = vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL
                append(&attachment_refs, color_attachment_ref)

                subpass.colorAttachmentCount = 1
                subpass.pColorAttachments = &attachment_refs[len(attachment_refs) - 1]

                dependency.srcStageMask |= {vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT}
                dependency.dstStageMask |= {vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT}
                dependency.dstAccessMask |= {vk.AccessFlag.COLOR_ATTACHMENT_WRITE}
            }
            case .Depth:
            {
                depth_attachment := vk.AttachmentDescription{}
                depth_attachment.format = attachemnt.format
                depth_attachment.samples = attachemnt.sample_count

                depth_attachment.loadOp = vk.AttachmentLoadOp.CLEAR
                depth_attachment.storeOp = vk.AttachmentStoreOp.DONT_CARE

                depth_attachment.stencilLoadOp = vk.AttachmentLoadOp.DONT_CARE
                depth_attachment.stencilStoreOp = vk.AttachmentStoreOp.DONT_CARE

                depth_attachment.initialLayout = vk.ImageLayout.UNDEFINED
                depth_attachment.finalLayout = vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL
                append(&attachments, depth_attachment)

                color_attachment_ref := vk.AttachmentReference{}
                color_attachment_ref.attachment = u32(len(attachments) - 1)
                color_attachment_ref.layout = vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL
                append(&attachment_refs, color_attachment_ref)

                subpass.pDepthStencilAttachment = &attachment_refs[len(attachment_refs) - 1]

                dependency.srcStageMask |= {vk.PipelineStageFlag.EARLY_FRAGMENT_TESTS}
                dependency.dstStageMask |= {vk.PipelineStageFlag.EARLY_FRAGMENT_TESTS}
                dependency.dstAccessMask |= {vk.AccessFlag.DEPTH_STENCIL_ATTACHMENT_WRITE}
            }
            case .Resolve:
            {
                color_resolve_attachment := vk.AttachmentDescription{}
                color_resolve_attachment.format = attachemnt.format
                color_resolve_attachment.samples = attachemnt.sample_count

                color_resolve_attachment.loadOp = vk.AttachmentLoadOp.DONT_CARE
                color_resolve_attachment.storeOp = vk.AttachmentStoreOp.STORE

                color_resolve_attachment.stencilLoadOp = vk.AttachmentLoadOp.DONT_CARE
                color_resolve_attachment.stencilStoreOp = vk.AttachmentStoreOp.DONT_CARE

                color_resolve_attachment.initialLayout = vk.ImageLayout.UNDEFINED
                color_resolve_attachment.finalLayout = vk.ImageLayout.GENERAL
                append(&attachments, color_resolve_attachment)

                color_attachment_ref := vk.AttachmentReference{}
                color_attachment_ref.attachment = u32(len(attachments) - 1)
                color_attachment_ref.layout = vk.ImageLayout.COLOR_ATTACHMENT_OPTIMAL
                append(&attachment_refs, color_attachment_ref)

                subpass.pResolveAttachments = &attachment_refs[len(attachment_refs) - 1]
            }
        }
    }

    render_pass_info := vk.RenderPassCreateInfo{}
    render_pass_info.sType = vk.StructureType.RENDER_PASS_CREATE_INFO

    render_pass_info.attachmentCount = u32(len(attachments))
    render_pass_info.pAttachments = raw_data(attachments)

    render_pass_info.subpassCount = 1
    render_pass_info.pSubpasses = &subpass

    render_pass_info.dependencyCount = 1;
    render_pass_info.pDependencies = &dependency;

    render_pass := vk.RenderPass{}
    assert(
        vk.CreateRenderPass(
            device_context.device,
            &render_pass_info,
            nil,
            &render_pass
        ) == vk.Result.SUCCESS
    )
    return render_pass
}

vk_create_graphics_pipeline :: proc(
    device_context : ^device.DeviceContext,
    vertex_types : []typeid,
    instance_types : []typeid,
    render_pass : vk.RenderPass,
    shader_group : shader_group.ShaderGroupContext,
    enable_multisampleing : bool,
    subpass_index : u32
) -> (vk.PipelineLayout, vk.Pipeline)
{
    assert(len(shader_group.shader_modules) > 0)
    shader_stages : sa.Small_Array(8, vk.PipelineShaderStageCreateInfo)
    for sm in shader_group.shader_modules
    {
        shader_stage_info := vk.PipelineShaderStageCreateInfo{}
        shader_stage_info.sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO
        switch sm.type
        {
            case .VERTEX: shader_stage_info.stage = {vk.ShaderStageFlag.VERTEX}
            case .FRAGMENT: shader_stage_info.stage = {vk.ShaderStageFlag.FRAGMENT}
            case .COMPUTE: panic("cannot have compute shader in graphics pipeline")
        }
        shader_stage_info.module = sm.vk_shader_module
        shader_stage_info.pName = "main"
        sa.append(&shader_stages, shader_stage_info)
    }

    dynamic_states := []vk.DynamicState{
        vk.DynamicState.VIEWPORT,
        vk.DynamicState.SCISSOR
    }

    dynamic_state_info := vk.PipelineDynamicStateCreateInfo{}
    dynamic_state_info.sType = vk.StructureType.PIPELINE_DYNAMIC_STATE_CREATE_INFO
    dynamic_state_info.dynamicStateCount = u32(len(dynamic_states))
    dynamic_state_info.pDynamicStates = raw_data(dynamic_states)

    // setup vertex input info
    vertex_input_info := vk.PipelineVertexInputStateCreateInfo{}
    vertex_input_info.sType = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO

    binding_descriptions := make([dynamic]vk.VertexInputBindingDescription)
    defer delete(binding_descriptions)
    binding_attribute_descriptions := make([dynamic]vk.VertexInputAttributeDescription)
    defer delete(binding_attribute_descriptions)
    for i in 0..<len(vertex_types)
    {
        vertex_binding_description, vertex_binding_attribute_description := calculate_binding_description(
            u32(len(binding_descriptions)), u32(len(binding_attribute_descriptions)),
            vertex_types[i], vk.VertexInputRate.VERTEX
        )
        append(&binding_descriptions, vertex_binding_description)
        append(&binding_attribute_descriptions, ..vertex_binding_attribute_description)
    }
    for i in 0..<len(instance_types)
    {
        instance_binding_description, instance_binding_attribute_description := calculate_binding_description(
            u32(len(binding_descriptions)), u32(len(binding_attribute_descriptions)),
            instance_types[i], vk.VertexInputRate.INSTANCE
        )
        append(&binding_descriptions, instance_binding_description)
        append(&binding_attribute_descriptions, ..instance_binding_attribute_description)
        delete(instance_binding_attribute_description)
    }

    vertex_input_info.vertexBindingDescriptionCount = u32(len(binding_descriptions))
    vertex_input_info.pVertexBindingDescriptions = raw_data(binding_descriptions)
    vertex_input_info.vertexAttributeDescriptionCount = u32(len(binding_attribute_descriptions))
    vertex_input_info.pVertexAttributeDescriptions = raw_data(binding_attribute_descriptions)

    //
    input_assembly := vk.PipelineInputAssemblyStateCreateInfo{}
    input_assembly.sType = vk.StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
    input_assembly.topology = vk.PrimitiveTopology.TRIANGLE_LIST
    input_assembly.primitiveRestartEnable = false

    viewport_state := vk.PipelineViewportStateCreateInfo{}
    viewport_state.sType = vk.StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO
    viewport_state.viewportCount = 1
    viewport_state.scissorCount = 1

    rasterizer := vk.PipelineRasterizationStateCreateInfo{}
    rasterizer.sType = vk.StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO
    rasterizer.depthClampEnable = false
    rasterizer.rasterizerDiscardEnable = false
    rasterizer.polygonMode = vk.PolygonMode.FILL
    rasterizer.lineWidth = 1
    rasterizer.cullMode = {vk.CullModeFlag.BACK}
    rasterizer.frontFace = vk.FrontFace.CLOCKWISE
    rasterizer.depthBiasEnable = false

    // controlls weather we sample multiple triangles around the edges for anitalisaing
    multisampling := vk.PipelineMultisampleStateCreateInfo{}
    multisampling.sType = vk.StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
    multisampling.sampleShadingEnable = false
    if enable_multisampleing
    {
        multisampling.rasterizationSamples = {device_context.physical_device_max_useable_sample_count}
    }
    else
    {
        multisampling.rasterizationSamples = {vk.SampleCountFlag._1}
    }
    multisampling.minSampleShading = 1
    multisampling.pSampleMask = nil
    multisampling.alphaToCoverageEnable = false
    multisampling.alphaToOneEnable = false

    // controll how the output of the fragment shader is bleneded onto the exisitng frame buffer
    color_blend_attachment := vk.PipelineColorBlendAttachmentState{}
    color_blend_attachment.colorWriteMask = {
        vk.ColorComponentFlag.R,
        vk.ColorComponentFlag.G,
        vk.ColorComponentFlag.B,
        vk.ColorComponentFlag.A
    }
    color_blend_attachment.blendEnable = false

    color_blending := vk.PipelineColorBlendStateCreateInfo{}
    color_blending.sType = vk.StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
    color_blending.logicOpEnable = false
    color_blending.attachmentCount = 1
    color_blending.pAttachments = &color_blend_attachment

    // depth stencil
    depth_stencil := vk.PipelineDepthStencilStateCreateInfo{}
    depth_stencil.sType = vk.StructureType.PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
    depth_stencil.depthTestEnable = true
    depth_stencil.depthWriteEnable = true

    depth_stencil.depthCompareOp = vk.CompareOp.LESS

    depth_stencil.depthBoundsTestEnable = false
    depth_stencil.minDepthBounds = 0
    depth_stencil.maxDepthBounds = 1
    depth_stencil.stencilTestEnable = false

    // make pipeline layout
    pipeline_layout_info := vk.PipelineLayoutCreateInfo{};
    pipeline_layout_info.sType = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO;
    pipeline_layout_info.setLayoutCount = u32(len(shader_group.set_layouts))
    pipeline_layout_info.pSetLayouts = raw_data(shader_group.set_layouts)

    pipeline_layout := vk.PipelineLayout{}
    assert(
        vk.CreatePipelineLayout(
            device_context.device,
            &pipeline_layout_info,
            nil,
            &pipeline_layout
        ) == vk.Result.SUCCESS
    )

    graphics_pipeline_info := vk.GraphicsPipelineCreateInfo{}
    graphics_pipeline_info.sType = vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO
    shader_stages_slice := sa.slice(&shader_stages)
    graphics_pipeline_info.stageCount = u32(len(shader_stages_slice))
    graphics_pipeline_info.pStages = raw_data(shader_stages_slice)

    graphics_pipeline_info.pVertexInputState = &vertex_input_info
    graphics_pipeline_info.pInputAssemblyState = &input_assembly
    graphics_pipeline_info.pViewportState = &viewport_state
    graphics_pipeline_info.pRasterizationState = &rasterizer
    graphics_pipeline_info.pMultisampleState = &multisampling
    graphics_pipeline_info.pDepthStencilState = nil
    graphics_pipeline_info.pColorBlendState = &color_blending
    graphics_pipeline_info.pDynamicState = &dynamic_state_info
    graphics_pipeline_info.pDepthStencilState = &depth_stencil

    graphics_pipeline_info.layout = pipeline_layout
    graphics_pipeline_info.renderPass = render_pass
    graphics_pipeline_info.subpass = subpass_index

    graphics_pipeline := vk.Pipeline{}
    assert(
        vk.CreateGraphicsPipelines(
            device_context.device,
            0,
            1,
            &graphics_pipeline_info,
            nil,
            &graphics_pipeline
        ) == vk.Result.SUCCESS
    )

    return pipeline_layout, graphics_pipeline
}

calculate_binding_description :: proc(binding : u32, location_offset : u32, t : typeid, input_rate : vk.VertexInputRate) -> (vk.VertexInputBindingDescription, []vk.VertexInputAttributeDescription)
{
    type_info := type_info_of(t)

    bindingDescription := vk.VertexInputBindingDescription{}
    bindingDescription.binding = binding // the binding number here should match up with vk.CmdBindVertexBuffers binding i think
    bindingDescription.stride = u32(type_info.size)
    bindingDescription.inputRate = input_rate

    struct_info_named, struct_is_named := type_info.variant.(runtime.Type_Info_Named)
    maybe_struct_info : runtime.Type_Info
    if struct_is_named
    {
        maybe_struct_info = struct_info_named.base^
    }
    else
    {
        maybe_struct_info = type_info^
    }

    struct_info, is_struct := maybe_struct_info.variant.(runtime.Type_Info_Struct)
    if is_struct
    {
        vertex_input_attribute_description := make([]vk.VertexInputAttributeDescription, struct_info.field_count)
        for i in 0..<struct_info.field_count
        {
            vertex_input_attribute_description[i].binding = binding
            vertex_input_attribute_description[i].location = u32(i) + location_offset
            vertex_input_attribute_description[i].format = base_type_to_format(struct_info.types[i].id)
            vertex_input_attribute_description[i].offset = u32(struct_info.offsets[i])
        }
        return bindingDescription, vertex_input_attribute_description
    }
    else
    {
        vertex_input_attribute_description := make([]vk.VertexInputAttributeDescription, 1)
        vertex_input_attribute_description[0].binding = binding
        vertex_input_attribute_description[0].location = location_offset
        vertex_input_attribute_description[0].format = base_type_to_format(maybe_struct_info.id)
        vertex_input_attribute_description[0].offset = 0
        return bindingDescription, vertex_input_attribute_description
    }
}

base_type_to_format :: proc(t : typeid) -> vk.Format
{
    switch t
    {
        case [4]f32: {
            return vk.Format.R32G32B32A32_SFLOAT
        }
        case [3]f32: {
            return vk.Format.R32G32B32_SFLOAT
        }
        case [2]f32: {
            return vk.Format.R32G32_SFLOAT
        }
        case f32: {
            return vk.Format.R32_SFLOAT
        }
        case u32: {
            return vk.Format.R32_UINT
        }
        case quaternion128: {
            return vk.Format.R32G32B32A32_SFLOAT
        }
        case: panic("oh no struct has unsupported type")
    }
}
