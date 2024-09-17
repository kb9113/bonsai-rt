package mesh

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:fmt"
import "../color"

Vec2 :: [2]f32
Vec3 :: [3]f32

Triangle :: struct #packed
{
    vert_indecies : [3]u32,
    uv_indecies : [3]u32,
    normal_indecies : [3]u32,
    material_index : u32,
}

make_triangle :: proc(
    material_index : u32,
    vert_indecies : [3]u32,
    uv_indecies : [3]u32 = [3]u32{},
    normal_indecies : [3]u32 = [3]u32{}
) -> Triangle
{
    return Triangle{
        vert_indecies,
        uv_indecies,
        normal_indecies,
        material_index
    }
}

Mesh :: struct
{
    verts : [dynamic]Vec3,
    uvs : [dynamic]Vec3,
    normals : [dynamic]Vec3,
    tris : [dynamic]Triangle,
}

transform_mesh :: proc(m : ^Mesh, t : matrix[4, 4]f32)
{
    for i in 0..<len(m.verts)
    {
        m.verts[i] = (t * [4]f32{m.verts[i].x, m.verts[i].y, m.verts[i].z, 1}).xyz
    }
}

reverse_winding_order :: proc(m : ^Mesh)
{
    for &tri in m.tris
    {
        tmp := tri.vert_indecies[0]
        tri.vert_indecies[0] = tri.vert_indecies[1]
        tri.vert_indecies[1] = tmp

        tmp = tri.normal_indecies[0]
        tri.normal_indecies[0] = tri.normal_indecies[1]
        tri.normal_indecies[1] = tmp

        tmp = tri.uv_indecies[0]
        tri.uv_indecies[0] = tri.uv_indecies[1]
        tri.uv_indecies[1] = tmp
    }
}

mesh_merge :: proc(l : Mesh, r : Mesh) -> Mesh
{
    ans := Mesh{}
    reserve(&ans.verts, len(l.verts) + len(r.verts))
    for v in l.verts
    {
        append(&ans.verts, v)
    }
    for v in r.verts
    {
        append(&ans.verts, v)
    }

    reserve(&ans.normals, len(l.normals) + len(r.normals))
    for n in l.normals
    {
        append(&ans.normals, n)
    }
    for n in r.normals
    {
        append(&ans.normals, n)
    }

    reserve(&ans.uvs, len(l.uvs) + len(r.uvs))
    for uv in l.uvs
    {
        append(&ans.uvs, uv)
    }
    for uv in r.uvs
    {
        append(&ans.uvs, uv)
    }

    reserve(&ans.tris, len(l.tris) + len(r.tris))
    for tri in l.tris
    {
        append(&ans.tris, tri)
    }
    for tri in r.tris
    {
        append(&ans.tris, Triangle{
            [3]u32{
                u32(len(l.verts)) + tri.vert_indecies[0],
                u32(len(l.verts)) + tri.vert_indecies[1],
                u32(len(l.verts)) + tri.vert_indecies[2]
            },
            [3]u32{
                u32(len(l.uvs)) + tri.uv_indecies[0],
                u32(len(l.uvs)) + tri.uv_indecies[1],
                u32(len(l.uvs)) + tri.uv_indecies[2]
            },
            [3]u32{
                u32(len(l.normals)) + tri.normal_indecies[0],
                u32(len(l.normals)) + tri.normal_indecies[1],
                u32(len(l.normals)) + tri.normal_indecies[2]
            },
            tri.material_index
        })
    }
    return ans
}

// translates the mesh so the center of the mesh is 0, 0, 0 returns the required translation to translate back to the original
recenter_mesh :: proc(m : ^Mesh) -> [3]f32
{
    min_x := math.INF_F32
    max_x := math.NEG_INF_F32
    min_y := math.INF_F32
    max_y := math.NEG_INF_F32
    min_z := math.INF_F32
    max_z := math.NEG_INF_F32

    // calulate bounds
    for v in m.verts
    {
        min_x = math.min(min_x, v.x)
        max_x = math.max(max_x, v.x)
        min_y = math.min(min_y, v.y)
        max_y = math.max(max_y, v.y)
        min_z = math.min(min_z, v.z)
        max_z = math.max(max_z, v.z)
    }

    inv_translation_vector := [3]f32{(max_x - min_x) / 2, (max_y - min_y) / 2, (max_y - min_y) / 2}

    for &v in m.verts
    {
        v -= inv_translation_vector
    }
    return inv_translation_vector
}

offset_materials :: proc(m : ^Mesh, offset : u32)
{
    for &tri in m.tris
    {
        tri.material_index += offset
    }
}

flip_uvs_y_coord :: proc(m : ^Mesh)
{
    for &uv in m.uvs
    {
        uv = [3]f32{uv.x, 1 - uv.y, uv.z}
    }
}
