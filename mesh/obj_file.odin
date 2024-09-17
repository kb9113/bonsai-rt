package mesh

import "core:math"
import "core:math/linalg"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"

WindingOrder :: enum
{
    Clockwise,
    CounterClockwise
}

read_obj_file_to_mesh :: proc(
    file_path : string
) -> Mesh
{
    obj_file := read_obj_file(file_path)
	return obj_file.mesh
}

ObjectFile :: struct
{
    objects : [dynamic]ObjectFileObject,
    mesh : Mesh
}

ObjectFileObject :: struct
{
    name : string,
    face_offset : u32,
    face_count : u32,
}

read_obj_file :: proc(
    file_path : string
) -> ObjectFile
{
    data, ok := os.read_entire_file(file_path, context.allocator)
	assert(ok)
	defer delete(data, context.allocator)

	ans := ObjectFile{}

	it := string(data)
	for line in strings.split_lines_iterator(&it)
	{
	    ss := strings.split(line, " ")
		if ss[0] == "#"
		{
		    continue;
		}
		if ss[0] == "o"
		{
		    ofo := ObjectFileObject{}
			ofo.name = strings.join(ss[1:], " ")
			ofo.face_offset = u32(len(ans.mesh.tris))
			append(&ans.objects, ofo)
		}
		if ss[0] == "v"
		{
			f1, ok1 := strconv.parse_f32(ss[1])
			assert(ok1)
			f2, ok2 := strconv.parse_f32(ss[2])
			assert(ok2)
			f3, ok3 := strconv.parse_f32(ss[3])
			assert(ok3)
			vert := [3]f32{f1, f2, f3}
			append(&ans.mesh.verts, [3]f32{vert[0], vert[1], vert[2]})
		}
		else if ss[0] == "vt"
		{
            f1, ok1 := strconv.parse_f32(ss[1])
            assert(ok1)
            f2, ok2 := strconv.parse_f32(ss[2])
            assert(ok2)
            if len(ss) == 3
            {
                append(&ans.mesh.uvs, [3]f32{f1, f2, 0})
            }
            else
            {
                f3, ok3 := strconv.parse_f32(ss[3])
                assert(ok3)
                append(&ans.mesh.uvs, [3]f32{f1, f2, f3})
            }
		}
		else if ss[0] == "vn"
		{
            f1, ok1 := strconv.parse_f32(ss[1])
            assert(ok1)
            f2, ok2 := strconv.parse_f32(ss[2])
            assert(ok2)
            f3, ok3 := strconv.parse_f32(ss[3])
			assert(ok3)
            append(&ans.mesh.normals, [3]f32{f1, f2, f3})
		}
		else if ss[0] == "f"
		{
			for i in 0..<(len(ss) - 3)
			{
                if len(ans.objects) > 0
                {
                    ans.objects[len(ans.objects) - 1].face_count += 1
                }

                parts1 := strings.split(ss[1], "/")
                parts2 := strings.split(ss[i + 2], "/")
                parts3 := strings.split(ss[i + 3], "/")

                vi1, viok1 := strconv.parse_u64(parts1[0])
    			assert(viok1)
    			vi2, viok2 := strconv.parse_u64(parts2[0])
    			assert(viok2)
    			vi3, viok3 := strconv.parse_u64(parts3[0])
    			assert(viok3)

                tri := Triangle{}
    			tri.vert_indecies = [3]u32{
         			u32(vi1 - 1),
    				u32(vi2 - 1),
    				u32(vi3 - 1),
                }

    			if len(parts1) >= 2
    			{
                    uv1, uvok1 := strconv.parse_u64(parts1[1])
         			assert(uvok1)
         			uv2, uvok2 := strconv.parse_u64(parts2[1])
         			assert(uvok2)
         			uv3, uvok3 := strconv.parse_u64(parts3[1])
         			assert(uvok3)

                    tri.uv_indecies = [3]u32{
                        u32(uv1 - 1),
                        u32(uv2 - 1),
                        u32(uv3 - 1),
                    }
    			}

    			if len(parts1) >= 3
    			{
                    n1, nok1 := strconv.parse_u64(parts1[2])
         			assert(nok1)
         			n2, nok2 := strconv.parse_u64(parts2[2])
         			assert(nok2)
         			n3, nok3 := strconv.parse_u64(parts3[2])
         			assert(nok3)

                    tri.normal_indecies = [3]u32{
             			u32(n1 - 1),
        				u32(n2 - 1),
        				u32(n3 - 1),
         			}
    			}

    			append(&ans.mesh.tris, tri)
			}
		}
	}
	return ans
}
