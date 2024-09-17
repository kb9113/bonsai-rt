package color

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:math"
import "core:time"
import "core:math/linalg"
import "vendor:glfw"
import vk "vendor:vulkan"
import "vendor:stb/image"

XYZColor :: distinct [3]f64

gaussian_fn :: proc(x : f64, u : f64, t1 : f64, t2 : f64) -> f64
{
    if x < u
    {
        return math.exp_f64(-t1 * t1 * (x - u) * (x - u) / 2)
    }
    else
    {
        return math.exp_f64(-t2 * t2 * (x - u) * (x - u) / 2)
    }
}

approximate_xyz_color_matching_function :: proc(l : f64) -> (f64, f64, f64)
{
    x := 1.056 * gaussian_fn(l, 599.8, 0.0264, 0.0323) + 0.362 * gaussian_fn(l, 442.0, 0.0624, 0.0374) -
         0.065 * gaussian_fn(l, 501.1, 0.0490, 0.0382)
    y := 0.821 * gaussian_fn(l, 568.8, 0.0213, 0.0247) + 0.286 * gaussian_fn(l, 530.9, 0.0613, 0.0322)
    z := 1.217 * gaussian_fn(l, 437.0, 0.0845, 0.0278) + 0.681 * gaussian_fn(l, 459.0, 0.0385, 0.0725)
    return x, y, z
}

approximate_d65_whitepoint_function :: proc(l : f64) -> f64
{
    return 1.12821052444 * gaussian_fn(l, 452.69937031848269, 0.01736858706922958, 0.0043111772849707937)
}

xyz_color_matching_function :: proc(l : f64) -> (f64, f64, f64)
{
    table_lookup_index := i32(math.round(l - 360))
    table_lookup_index = clamp(table_lookup_index, 0, len(XYZ_COLOR_MATCH_FUNCTIONS_STARTING_AT_360NM))
    ans := XYZ_COLOR_MATCH_FUNCTIONS_STARTING_AT_360NM[table_lookup_index]
    return ans.x, ans.y, ans.z
}

d65_whitepoint_function :: proc(l : f64) -> f64
{
    table_lookup_index := i32(math.round(l - 300))
    table_lookup_index = clamp(table_lookup_index, 0, len(D65_WHITEPOINT_FUNCTION_STARTING_AT_300NM))
    return D65_WHITEPOINT_FUNCTION_STARTING_AT_300NM[table_lookup_index]
}
