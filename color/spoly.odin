package color

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:math"
import "core:time"
import "core:log"
import "core:math/linalg"
import "vendor:glfw"
import vk "vendor:vulkan"
import "vendor:stb/image"

SPolyColor :: distinct [3]f64

sigmoid :: proc(x : f64) -> f64
{
    return 0.5 + x / (2 * math.sqrt(1 + x * x))
}

sigmoid_derivative :: proc(x : f64) -> f64
{
    return f64(1) / (2 * math.pow_f64(x * x + 1, f64(3) / 2))
}

sigmoid_polynomial :: proc(l : f64, p : [3]f64) -> f64
{
    return sigmoid(p[2] * l * l + p[1] * l + p[0])
}

sigmoid_polynomial_derivatives ::  proc(l : f64, p : [3]f64) -> [3]f64
{
    sd := sigmoid_derivative(p[2] * l * l + p[1] * l + p[0])
    return [3]f64{sd * 1, sd * l, sd * l * l}
}

// evaluates the spoly surface spectra under a given light spectrum
_spoly_to_xyz :: proc(
    p : SPolyColor,
    color_match_function : proc(f64) -> (f64, f64, f64),
    white_spectrum : proc(f64) -> f64
) -> XYZColor
{
    // we use lots of rectangular priems to integrate
    sum_x : f64 = 0
    sum_y : f64 = 0
    sum_z : f64 = 0

    y_integral : f64 = 0

    for i in WAVE_LENGTH_MIN..<WAVE_LENGTH_MAX
    {
        x, y, z := color_match_function(f64(i))
        white_point_value := white_spectrum(f64(i))
        sigmoid_polynomial_value := sigmoid_polynomial(f64(i), [3]f64{p.x, p.y, p.z})
        sum_x += sigmoid_polynomial_value * x * white_point_value
        sum_y += sigmoid_polynomial_value * y * white_point_value
        sum_z += sigmoid_polynomial_value * z * white_point_value
        y_integral += y
    }

    return XYZColor{
        sum_x / y_integral,
        sum_y / y_integral,
        sum_z / y_integral
    }
}

// returns the spoly color and then the error
// white_spectrum is the lighting conditions under which the spoly color spectrum will be perseved as the input xyz color value
_xyz_to_spoly :: proc(
    xyz : XYZColor,
    color_match_function : proc(f64) -> (f64, f64, f64),
    white_spectrum : proc(f64) -> f64
) -> (SPolyColor, f64)
{
    guess_p := [3]f64{-249, 1, -0.001}
    target := [3]f64{xyz.x, xyz.y, xyz.z}
    error := math.INF_F64

    for i in 0..<10000
    {
        // we use approximate_d65_whitepoint_function so that under white light a spoly with a spectrum equal to 1 at all points is white in xyz color
        jacobian := _spoly_to_xyz_jacobian(SPolyColor(guess_p), color_match_function, white_spectrum)

        res_xyz := _spoly_to_xyz(SPolyColor(guess_p), color_match_function, white_spectrum)
        res := [3]f64{res_xyz.x, res_xyz.y, res_xyz.z} - target
        error = linalg.length(res)

        if math.abs(linalg.determinant(jacobian)) < 1e-30
        {
            // we will have alot of numerical instability if the jacobian is very small so we stop
            // this is fine since if we stop here we are likley very close to a local minimum anyway
            break;
        }

        if error < 1e-4
        {
            break;
        }

        d_guess := linalg.inverse(jacobian) * res
        if linalg.length(d_guess) < 0.000001
        {
            break;
        }
        guess_p = guess_p - d_guess * 8 // we times by 8 as we have figured out it makes it zoom to converge


        m := math.max(math.max(guess_p[0], guess_p[1]), guess_p[2]);

        guess_p = linalg.clamp(guess_p, [3]f64{-1000, -1000, -1000}, [3]f64{1000, 1000, 1000})
    }
    return SPolyColor(guess_p), error
}

_spoly_to_xyz_jacobian :: proc(
    p : SPolyColor,
    color_match_function : proc(f64) -> (f64, f64, f64),
    white_spectrum : proc(f64) -> f64
) -> matrix[3, 3]f64
{
    sum_x := [3]f64{}
    sum_y := [3]f64{}
    sum_z := [3]f64{}

    for i in WAVE_LENGTH_MIN..<WAVE_LENGTH_MAX
    {
        x, y, z := color_match_function(f64(i))
        white_point_value := white_spectrum(f64(i))
        sigmoid_polynomial_derivative := sigmoid_polynomial_derivatives(f64(i), [3]f64{p.x, p.y, p.z})
        sum_x += sigmoid_polynomial_derivative * x * white_point_value
        sum_y += sigmoid_polynomial_derivative * y * white_point_value
        sum_z += sigmoid_polynomial_derivative * z * white_point_value
    }

    return matrix[3, 3]f64{
        sum_x[0], sum_x[1], sum_x[2],
        sum_y[0], sum_y[1], sum_y[2],
        sum_z[0], sum_z[1], sum_z[2],
    }
}

spoly_to_xyz_d65 :: proc(p : SPolyColor) -> XYZColor
{
    return _spoly_to_xyz(p, xyz_color_matching_function, d65_whitepoint_function)
}

xyz_d65_to_spoly :: proc(xyz : XYZColor) -> (SPolyColor, f64)
{
    return _xyz_to_spoly(xyz, xyz_color_matching_function, d65_whitepoint_function)
}

approximate_spoly_to_xyz_d65 :: proc(p : SPolyColor) -> XYZColor
{
    return _spoly_to_xyz(p, approximate_xyz_color_matching_function, approximate_d65_whitepoint_function)
}

approximate_xyz_d65_to_spoly :: proc(xyz : XYZColor) -> (SPolyColor, f64)
{
    return _xyz_to_spoly(xyz, approximate_xyz_color_matching_function, approximate_d65_whitepoint_function)
}
