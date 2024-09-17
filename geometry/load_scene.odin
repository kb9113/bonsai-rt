package geometry

import vk "vendor:vulkan"
import "../acorn/device"
import "../acorn/resource"
import "../acorn/pipeline"
import "../acorn/shader_module"
import "../acorn/present"
import "../scene"
import "../color"
import "core:fmt"
import "core:math/linalg"

find_and_build_corresponding_material :: proc(s : scene.Scene, material_name : string) -> GPUMaterial
{
    // now find the corresponding material
    for m in s.materials
    {
        ans := GPUMaterial{}
        switch v in m
        {
            case scene.SceneMaterialDiffuse:
            {
                if v.material_name != material_name { continue }
                ans.material_type = 0
                color_linear_rgb := color.LinearRGBColor{f64(v.color.r), f64(v.color.g), f64(v.color.b)}
                color_xyz := color.linear_rgb_to_xyz(color_linear_rgb)
                switch s.settings.internal_color_mode
                {
                    case .XYZD65:
                    {
                        color_spoly, err := color.xyz_d65_to_spoly(color_xyz)
                        ans.spoly_color = [3]f32{f32(color_spoly.x), f32(color_spoly.y), f32(color_spoly.z)}
                    }
                    case .APPROXXYZD65:
                    {
                        color_spoly, err := color.approximate_xyz_d65_to_spoly(color_xyz)
                        ans.spoly_color = [3]f32{f32(color_spoly.x), f32(color_spoly.y), f32(color_spoly.z)}
                    }
                }
                return ans
            }
            case scene.SceneMaterialConductive:
            {
                if v.material_name != material_name { continue }
                ans.material_type = 1
                color_linear_rgb := color.LinearRGBColor{f64(v.color.r), f64(v.color.g), f64(v.color.b)}
                color_xyz := color.linear_rgb_to_xyz(color_linear_rgb)
                switch s.settings.internal_color_mode
                {
                    case .XYZD65:
                    {
                        color_spoly, err := color.xyz_d65_to_spoly(color_xyz)
                        ans.spoly_color = [3]f32{f32(color_spoly.x), f32(color_spoly.y), f32(color_spoly.z)}
                    }
                    case .APPROXXYZD65:
                    {
                        color_spoly, err := color.approximate_xyz_d65_to_spoly(color_xyz)
                        ans.spoly_color = [3]f32{f32(color_spoly.x), f32(color_spoly.y), f32(color_spoly.z)}
                    }
                }
                ans.args[0] = v.ior
                ans.args[1] = v.ec
                return ans
            }
            case scene.SceneMaterialDieletric:
            {
                if v.material_name != material_name { continue }
                ans.material_type = 2
                color_linear_rgb := color.LinearRGBColor{f64(v.color.r), f64(v.color.g), f64(v.color.b)}
                color_xyz := color.linear_rgb_to_xyz(color_linear_rgb)
                switch s.settings.internal_color_mode
                {
                    case .XYZD65:
                    {
                        color_spoly, err := color.xyz_d65_to_spoly(color_xyz)
                        ans.spoly_color = [3]f32{f32(color_spoly.x), f32(color_spoly.y), f32(color_spoly.z)}
                    }
                    case .APPROXXYZD65:
                    {
                        color_spoly, err := color.approximate_xyz_d65_to_spoly(color_xyz)
                        ans.spoly_color = [3]f32{f32(color_spoly.x), f32(color_spoly.y), f32(color_spoly.z)}
                    }
                }
                ans.args[0] = v.ior
                return ans
            }
            case scene.SceneMaterialEmmisive:
            {
                if v.material_name != material_name { continue }
                ans.material_type = 3
                // color_srgb := color.SRGBColor{f64(v.color.r), f64(v.color.g), f64(v.color.b)}
                // color_linear_rgb := color.srgb_to_linear_rgb(color_srgb)
                color_linear_rgb := color.LinearRGBColor{f64(v.color.r), f64(v.color.g), f64(v.color.b)}
                color_xyz := color.linear_rgb_to_xyz(color_linear_rgb)
                switch s.settings.internal_color_mode
                {
                    case .XYZD65:
                    {
                        color_spoly, err := color.xyz_d65_to_spoly(color_xyz)
                        ans.spoly_color = [3]f32{f32(color_spoly.x), f32(color_spoly.y), f32(color_spoly.z)}
                    }
                    case .APPROXXYZD65:
                    {
                        color_spoly, err := color.approximate_xyz_d65_to_spoly(color_xyz)
                        ans.spoly_color = [3]f32{f32(color_spoly.x), f32(color_spoly.y), f32(color_spoly.z)}
                    }
                }
                ans.args[0] = v.strength
                return ans
            }
        }
    }
    fmt.panicf("no matching material found %s", material_name)
}

set_camera :: proc(
    device_context : ^device.DeviceContext,
    geometry_context : ^GeometryContext,
    pos : [3]f32,
    dir : [3]f32,
    up : [3]f32,
    size : f32
)
{
    ray_right_vector := linalg.normalize(linalg.cross(dir, up)) * size
    ray_up_vector := linalg.normalize(linalg.cross(ray_right_vector, dir)) * size

    geometry_context.camera_buffer.data[0] = matrix[4, 4]f32{
        ray_right_vector.x, ray_up_vector.x, dir.x, pos.x,
        ray_right_vector.y, ray_up_vector.y, dir.y, pos.y,
        ray_right_vector.z, ray_up_vector.z, dir.z, pos.z,
        0, 0, 0, 0
    }
}

load_scene :: proc(
    device_context : ^device.DeviceContext,
    geometry_context : ^GeometryContext,
    s : scene.Scene
)
{
    geometry_context.scene = s

    set_camera(
        device_context,
        geometry_context,
        s.camera.position,
        s.camera.direction,
        s.camera.up,
        s.camera.size
    )

    geometry_context.render_info_buffer.data[0].max_depth = s.settings.max_depth
    geometry_context.render_info_buffer.data[0].n_lights = u32(len(s.lights))

    obj_file_path_to_acceleration_structure := map[string]resource.AccelerationStructure{}
    obj_file_to_blocks := map[string][2]resource.Block{}

    n_verts := 0
    n_indexes := 0
    for key in s.obj_file_path_to_mesh
    {
        n_verts += len(s.obj_file_path_to_mesh[key].verts)
        n_indexes += len(s.obj_file_path_to_mesh[key].tris) * 3
    }

    geometry_context.vertex_multiblock_buffer = resource.make_multi_block_buffer(
        device_context, [4]f32, u32(n_verts), {vk.BufferUsageFlag.TRANSFER_DST}
    )
    geometry_context.index_multiblock_buffer = resource.make_multi_block_buffer(
        device_context, u32, u32(n_indexes), {vk.BufferUsageFlag.TRANSFER_DST}
    )

    for key in s.obj_file_path_to_mesh
    {
        m := s.obj_file_path_to_mesh[key]
        vertex_buffer_host_cohearent := resource.make_host_coherent_buffer(
            device_context, [4]f32, u32(len(m.verts))
        )

        index_buffer_host_cohearent := resource.make_host_coherent_buffer(
            device_context, u32, u32(len(m.tris) * 3)
        )

        for i in 0..<len(m.verts)
        {
            vertex_buffer_host_cohearent.data[i] = [4]f32{m.verts[i].x, m.verts[i].y, m.verts[i].z, 0}
        }

        for i in 0..<len(m.tris)
        {
            index_buffer_host_cohearent.data[i * 3] = m.tris[i].vert_indecies[0]
            index_buffer_host_cohearent.data[i * 3 + 1] = m.tris[i].vert_indecies[1]
            index_buffer_host_cohearent.data[i * 3 + 2] = m.tris[i].vert_indecies[2]
        }

        vertex_storeage_buffer := resource.make_storage_buffer(
            device_context, [4]f32, u32(len(m.verts)),
            {vk.BufferUsageFlag.TRANSFER_DST, vk.BufferUsageFlag.SHADER_DEVICE_ADDRESS, vk.BufferUsageFlag.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR}
        )

        index_storeage_buffer := resource.make_storage_buffer(
            device_context, u32, u32(len(m.tris) * 3),
            {vk.BufferUsageFlag.TRANSFER_DST, vk.BufferUsageFlag.SHADER_DEVICE_ADDRESS, vk.BufferUsageFlag.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR}
        )

        resource.copy_host_cohernet_buffer_to_storage_buffer(
            device_context,
            vertex_buffer_host_cohearent,
            vertex_storeage_buffer
        )

        resource.copy_host_cohernet_buffer_to_storage_buffer(
            device_context,
            index_buffer_host_cohearent,
            index_storeage_buffer
        )

        vertex_block := resource.copy_host_cohernet_buffer_to_mult_block_buffer(
            device_context,
            vertex_buffer_host_cohearent,
            &geometry_context.vertex_multiblock_buffer
        )

        index_block := resource.copy_host_cohernet_buffer_to_mult_block_buffer(
            device_context,
            index_buffer_host_cohearent,
            &geometry_context.index_multiblock_buffer
        )

        obj_file_path_to_acceleration_structure[key] = resource.create_bottom_level_acceleration_structure(
            device_context,
            vertex_storeage_buffer,
            index_storeage_buffer
        )
        obj_file_to_blocks[key] = [2]resource.Block{vertex_block, index_block}

        resource.delete_host_cohearnent_buffer(device_context, vertex_buffer_host_cohearent)
        resource.delete_host_cohearnent_buffer(device_context, index_buffer_host_cohearent)
    }

    bottom_level_acceleration_structure_instances := make([dynamic]resource.AccelerationStructureInstance)
    materials_host_cohearent_buffer := resource.make_host_coherent_buffer(
        device_context, GPUMaterial, u32(len(s.objects) + len(s.lights))
    )
    geometry_context.material_buffer = resource.make_storage_buffer(
        device_context, GPUMaterial, u32(len(s.objects) + len(s.lights)),
        {vk.BufferUsageFlag.TRANSFER_DST}
    )

    geometry_info_host_cohearent_buffer := resource.make_host_coherent_buffer(
        device_context, GPUInstanceInfo, u32(len(s.objects) + len(s.lights))
    )
    geometry_context.geometry_info_buffer = resource.make_storage_buffer(
        device_context, GPUInstanceInfo, u32(len(s.objects) + len(s.lights)),
        {vk.BufferUsageFlag.TRANSFER_DST}
    )

    light_host_cohearent_buffer := resource.make_host_coherent_buffer(
        device_context, GPULight, u32(len(s.lights))
    )
    geometry_context.light_buffer = resource.make_storage_buffer(
        device_context, GPULight, u32(len(s.lights)),
        {vk.BufferUsageFlag.TRANSFER_DST}
    )

    for i in 0..<len(s.objects)
    {
        // make vertex and index buffer
        instance := resource.AccelerationStructureInstance{}
        instance.acceleration_structure = obj_file_path_to_acceleration_structure[s.objects[i].obj_file]
        instance.transform = s.objects[i].transform

        append(&bottom_level_acceleration_structure_instances, instance)

        materials_host_cohearent_buffer.data[i] = find_and_build_corresponding_material(s, s.objects[i].material_name)

        instance_info := GPUInstanceInfo{}
        instance_info.transform = s.objects[i].transform
        instance_info.vertex_buffer_start_index = obj_file_to_blocks[s.objects[i].obj_file][0].start_index
        instance_info.vertex_buffer_length = obj_file_to_blocks[s.objects[i].obj_file][0].length
        instance_info.index_buffer_start_index = obj_file_to_blocks[s.objects[i].obj_file][1].start_index
        instance_info.index_buffer_length = obj_file_to_blocks[s.objects[i].obj_file][1].length
        geometry_info_host_cohearent_buffer.data[i] = instance_info
    }

    for i in 0..<len(s.lights)
    {
        // make vertex and index buffer
        instance := resource.AccelerationStructureInstance{}
        instance.acceleration_structure = obj_file_path_to_acceleration_structure[s.lights[i].obj_file]
        instance.transform = s.lights[i].transform

        append(&bottom_level_acceleration_structure_instances, instance)

        materials_host_cohearent_buffer.data[len(s.objects) + i] = find_and_build_corresponding_material(s, s.lights[i].material_name)

        instance_info := GPUInstanceInfo{}
        instance_info.transform = s.lights[i].transform
        instance_info.vertex_buffer_start_index = obj_file_to_blocks[s.lights[i].obj_file][0].start_index
        instance_info.vertex_buffer_length = obj_file_to_blocks[s.lights[i].obj_file][0].length
        instance_info.index_buffer_start_index = obj_file_to_blocks[s.lights[i].obj_file][1].start_index
        instance_info.index_buffer_length = obj_file_to_blocks[s.lights[i].obj_file][1].length
        geometry_info_host_cohearent_buffer.data[len(s.objects) + i] = instance_info

        light := GPULight{}
        light.type = 0
        light.arg0 = u32(len(s.objects) + i)

        light_host_cohearent_buffer.data[i] = light
    }

    resource.copy_host_cohernet_buffer_to_storage_buffer(
        device_context,
        materials_host_cohearent_buffer,
        geometry_context.material_buffer
    )
    resource.delete_resource(device_context, materials_host_cohearent_buffer)

    resource.copy_host_cohernet_buffer_to_storage_buffer(
        device_context,
        geometry_info_host_cohearent_buffer,
        geometry_context.geometry_info_buffer
    )
    resource.delete_resource(device_context, geometry_info_host_cohearent_buffer)

    resource.copy_host_cohernet_buffer_to_storage_buffer(
        device_context,
        light_host_cohearent_buffer,
        geometry_context.light_buffer
    )
    resource.delete_resource(device_context, light_host_cohearent_buffer)

    geometry_context.top_level_acceleration_structure = resource.create_top_level_acceleration_structure(
        device_context,
        bottom_level_acceleration_structure_instances[:]
    )
}
