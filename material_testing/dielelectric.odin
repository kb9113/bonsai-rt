package material_testing

import "core:math/linalg"
import "core:math"
import "core:fmt"

refract :: proc(w_out : [3]f32, normal_x : [3]f32, eta_x : f32) -> [3]f32
{
    eta := eta_x
    normal := normal_x
    cos_theta_in := linalg.dot(normal, w_out);

    if cos_theta_in < 0
    {
        eta = 1 / eta;
        cos_theta_in = -cos_theta_in;
        normal = -normal;
    }

    sin_squared_theta_in := max(0, 1 - cos_theta_in * cos_theta_in);
    sin_squared_theta_out := sin_squared_theta_in / (eta * eta);

    if sin_squared_theta_out >= 1
    {
        return [3]f32{0, 0, 0};
    }

    cos_theta_out := math.sqrt(1 - sin_squared_theta_out);
    fmt.println(cos_theta_out)
    return linalg.normalize(-w_out / eta + (cos_theta_in / eta - cos_theta_out) * normal);
}

reflect :: proc(w_out : [3]f32, normal_x : [3]f32) -> [3]f32
{
    return -w_out + 2.0 * linalg.dot(w_out, normal_x) * normal_x
}

fresnell_equasion_dieletric :: proc(cos_theta_in_x : f32, eta_x : f32) -> f32
{
    cos_theta_in := cos_theta_in_x
    eta := eta_x
    cos_theta_in = clamp(cos_theta_in, -1, 1);
    if cos_theta_in < 0
    {
        eta = 1 / eta;
        cos_theta_in = -cos_theta_in;
    }

    sin_squared_theta_in := 1 - cos_theta_in * cos_theta_in;
    sin_squared_theta_out := sin_squared_theta_in / (eta * eta);
    if sin_squared_theta_out >= 1
    {
        return 1.0;
    }
    cos_theta_out := math.sqrt(1 - sin_squared_theta_out);

    r_parallel := (eta * cos_theta_in - cos_theta_out) /
        (eta * cos_theta_in + cos_theta_out);
    r_perpendicular := (cos_theta_in - eta * cos_theta_out) /
        (cos_theta_in + eta * cos_theta_out);

    return math.clamp((r_parallel * r_parallel + r_perpendicular * r_perpendicular) / 2.0, 0, 1);
}
