package scene

import "core:encoding/json"
import "core:os"
import "../mesh"
import "core:fmt"

Scene :: struct
{
    settings : SceneSettings,
    camera : SceneCamera,
    obj_file_path_to_mesh : map[string]mesh.Mesh,
    objects : []SceneObject,
    lights : []SceneLight,
    materials : []SceneMaterial
}

SceneObject :: struct
{
    material_name : string,
    obj_file : string,
    transform : matrix[4, 4]f32,
}

SceneLight :: struct
{
    type : string,
    material_name : string,
    obj_file : string,
    transform : matrix[4, 4]f32,
}

SceneMaterial :: union
{
    SceneMaterialDiffuse,
    SceneMaterialConductive,
    SceneMaterialDieletric,
    SceneMaterialEmissive
}

SceneMaterialDiffuse :: struct
{
    material_name : string,
    color : [3]f32
}

SceneMaterialDieletric :: struct
{
    material_name : string,
    color : [3]f32,
    ior : f32
}

SceneMaterialConductive :: struct
{
    material_name : string,
    color : [3]f32,
    ior : f32,
    ec : f32
}

SceneMaterialEmissive :: struct
{
    material_name : string,
    color : [3]f32,
    strength : f32
}

SceneInternalColorMode :: enum
{
    XYZD65,
    APPROXXYZD65
}

SceneIntegrator :: enum
{
    NNE
}

SceneSettings :: struct
{
    internal_color_mode : SceneInternalColorMode,
    integrator : SceneIntegrator,
    max_depth : u32,
    n_samples : u32,
    width : u32,
    height : u32
}

SceneCameraType :: enum
{
    PinHole
}

SceneCamera :: struct
{
    type : SceneCameraType,
    position : [3]f32,
    direction : [3]f32,
    up : [3]f32,
    size : f32,
}
/*
"type": "pinhole",
"position": [0, 1, 6.8],
"direction": [0, 0, -1],
"size": 0.172

*/

read_settings :: proc(json_obj : json.Object) -> SceneSettings
{
    ans := SceneSettings{}

    internal_color_mode, internal_color_mode_is_string := json_obj["internal_color_mode"].(json.String)
    assert(internal_color_mode_is_string)
    switch internal_color_mode
    {
        case "xyz_d65": ans.internal_color_mode = .XYZD65
        case "approx_xyz_d65": ans.internal_color_mode = .APPROXXYZD65
        case: panic("invalid internal_color_mode")
    }

    integrator, integrator_is_string := json_obj["integrator"].(json.String)
    assert(integrator_is_string)
    switch integrator
    {
        case "nne": ans.integrator = .NNE
        case: panic("invalid internal_color_mode")
    }

    max_depth, max_depth_is_float := json_obj["max_depth"].(json.Float)
    assert(max_depth_is_float)
    ans.max_depth = u32(max_depth)

    n_samples, n_samples_is_float := json_obj["n_samples"].(json.Float)
    assert(n_samples_is_float)
    ans.n_samples = u32(n_samples)

    width, width_is_float := json_obj["width"].(json.Float)
    assert(width_is_float)
    ans.width = u32(width)

    height, height_is_float := json_obj["height"].(json.Float)
    assert(height_is_float)
    ans.height = u32(height)

    return ans;
}

read_camera :: proc(json_obj : json.Object) -> SceneCamera
{
    ans := SceneCamera{}

    type, type_is_string := json_obj["type"].(json.String)
    assert(type_is_string)
    switch type
    {
        case "pinhole": ans.type = .PinHole
        case: panic("invalid type")
    }

    position, position_is_array := json_obj["position"].(json.Array)
    assert(position_is_array)

    for i in 0..<len(position)
    {
        position_component, position_component_is_float := position[i].(json.Float)
        assert(position_component_is_float)
        ans.position[i] = f32(position_component)
    }

    direction, direction_is_array := json_obj["direction"].(json.Array)
    assert(direction_is_array)

    for i in 0..<len(direction)
    {
        direction_component, direction_component_is_float := direction[i].(json.Float)
        assert(direction_component_is_float)
        ans.direction[i] = f32(direction_component)
    }

    up, up_is_array := json_obj["up"].(json.Array)
    assert(up_is_array)

    for i in 0..<len(up)
    {
        up_component, up_component_is_float := up[i].(json.Float)
        assert(up_component_is_float)
        ans.up[i] = f32(up_component)
    }

    size, size_is_float := json_obj["size"].(json.Float)
    assert(size_is_float)
    ans.size = f32(size)

    return ans
}

read_transform :: proc(transform_rows : (json.Array)) -> matrix[4, 4]f32
{
    ans := matrix[4, 4]f32{}
    for i in 0..<len(transform_rows)
    {
        transform_cells, transform_cells_is_array := transform_rows[i].(json.Array)
        assert(transform_cells_is_array)
        for j in 0..<len(transform_cells)
        {
            cell, cell_is_int := transform_cells[j].(json.Float)
            assert(cell_is_int)
            ans[i, j] = f32(cell)
        }
    }
    return ans
}

read_scene_object :: proc(json_obj : json.Object) -> SceneObject
{
    ans := SceneObject{}

    material_name, material_name_is_string := json_obj["material_name"].(json.String)
    assert(material_name_is_string)
    ans.material_name = material_name

    obj_file_path, obj_file_path_is_string := json_obj["obj_file"].(json.String)
    assert(obj_file_path_is_string)
    ans.obj_file = obj_file_path

    transform_rows, transform_is_array := json_obj["transform"].(json.Array)
    assert(transform_is_array)
    ans.transform = read_transform(transform_rows)

    return ans
}

read_scene_light :: proc(json_obj : json.Object) -> SceneLight
{
    ans := SceneLight{}

    type, type_is_string := json_obj["type"].(json.String)
    assert(type_is_string)
    ans.type = type

    material_name, material_name_is_string := json_obj["material_name"].(json.String)
    assert(material_name_is_string)
    ans.material_name = material_name

    obj_file_path, obj_file_path_is_string := json_obj["obj_file"].(json.String)
    assert(obj_file_path_is_string)
    ans.obj_file = obj_file_path

    transform_rows, transform_is_array := json_obj["transform"].(json.Array)
    assert(transform_is_array)
    ans.transform = read_transform(transform_rows)

    return ans
}

read_scene_material :: proc(json_obj : json.Object) -> SceneMaterial
{
    material_name, material_name_is_string := json_obj["material_name"].(json.String)
    assert(material_name_is_string)

    type, type_is_string := json_obj["type"].(json.String)
    assert(type_is_string)

    color, color_is_object := json_obj["color"].(json.Object)
    assert(color_is_object)

    color_r, color_r_is_int := color["r"].(json.Float)
    assert(color_r_is_int)
    color_g, color_g_is_int := color["g"].(json.Float)
    assert(color_g_is_int)
    color_b, color_b_is_int := color["b"].(json.Float)
    assert(color_b_is_int)

    switch type
    {
        case "diffuse":
        {
            ans := SceneMaterialDiffuse{}
            ans.material_name = material_name
            ans.color = [3]f32{
                f32(color_r),
                f32(color_g),
                f32(color_b),
            }
            return ans
        }
        case "emissive":
        {
            ans := SceneMaterialEmissive{}
            ans.material_name = material_name
            ans.color = [3]f32{
                f32(color_r),
                f32(color_g),
                f32(color_b),
            }

            strength, strength_is_float := json_obj["strength"].(json.Float)
            assert(strength_is_float)
            ans.strength = f32(strength)

            return ans
        }
        case "conductive":
        {
            ans := SceneMaterialConductive{}
            ans.material_name = material_name
            ans.color = [3]f32{
                f32(color_r),
                f32(color_g),
                f32(color_b),
            }

            ior, ior_is_float := json_obj["ior"].(json.Float)
            assert(ior_is_float)
            ans.ior = f32(ior)

            ec, ec_is_float := json_obj["ec"].(json.Float)
            assert(ec_is_float)
            ans.ec = f32(ec)

            return ans
        }
        case "dielectric":
        {
            ans := SceneMaterialDieletric{}
            ans.material_name = material_name
            ans.color = [3]f32{
                f32(color_r),
                f32(color_g),
                f32(color_b),
            }

            ior, ior_is_float := json_obj["ior"].(json.Float)
            assert(ior_is_float)
            ans.ior = f32(ior)

            return ans
        }
        case: fmt.panicf("invalid material type %s", type)
    }
}

read_scene :: proc(path : string) -> Scene
{
    file_bytes, file_read_ok := os.read_entire_file_from_filename(path)
    assert(file_read_ok)
    value, maybe_err := json.parse(file_bytes)
    assert(maybe_err == .None)

    root_object, root_is_object := value.(json.Object)
    assert(root_is_object)

    settings, settings_is_object := root_object["settings"].(json.Object)
    assert(settings_is_object)
    camera, camera_is_object := root_object["camera"].(json.Object)
    assert(camera_is_object)
    objects_array, objects_is_array := root_object["objects"].(json.Array)
    assert(objects_is_array)
    lights_array, lights_is_array := root_object["lights"].(json.Array)
    assert(lights_is_array)
    materials_array, materials_is_array := root_object["materials"].(json.Array)
    assert(materials_is_array)

    ans_obj_file_path_to_mesh : map[string]mesh.Mesh
    ans_objects := make([dynamic]SceneObject)
    ans_lights := make([dynamic]SceneLight)
    ans_materials := make([dynamic]SceneMaterial)

    ans_settings := read_settings(settings)
    ans_camera := read_camera(camera)

    for maybe_object in objects_array
    {
        object, is_objects := maybe_object.(json.Object)
        assert(is_objects)

        scene_object := read_scene_object(object)
        _, obj_file_in_map := ans_obj_file_path_to_mesh[scene_object.obj_file]
        if !obj_file_in_map
        {
            ans_obj_file_path_to_mesh[scene_object.obj_file] = mesh.read_obj_file_to_mesh(scene_object.obj_file)
        }
        append(&ans_objects, scene_object)
    }

    for maybe_light in lights_array
    {
        light, is_light := maybe_light.(json.Object)
        assert(is_light)

        scene_light := read_scene_light(light)
        _, obj_file_in_map := ans_obj_file_path_to_mesh[scene_light.obj_file]
        if !obj_file_in_map
        {
            ans_obj_file_path_to_mesh[scene_light.obj_file] = mesh.read_obj_file_to_mesh(scene_light.obj_file)
        }
        append(&ans_lights, scene_light)
    }

    for maybe_material in materials_array
    {
        material, is_material := maybe_material.(json.Object)
        assert(is_material)
        append(&ans_materials, read_scene_material(material))
    }

    ans := Scene{}
    ans.settings = ans_settings
    ans.camera = ans_camera
    ans.obj_file_path_to_mesh = ans_obj_file_path_to_mesh
    ans.objects = ans_objects[:]
    ans.lights = ans_lights[:]
    ans.materials = ans_materials[:]
    return ans
}
