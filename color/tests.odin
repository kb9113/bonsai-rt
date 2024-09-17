package color

import "core:testing"
import "core:fmt"
import "core:log"
import "core:math/linalg"

@(test)
spoly_color_test :: proc(t: ^testing.T)
{
    test_colors := []SRGBU8Color{
        SRGBU8Color{255, 255, 255},
        SRGBU8Color{0, 255, 255},
        SRGBU8Color{0, 0, 255},
        SRGBU8Color{0, 0, 0},
        SRGBU8Color{34, 167, 89},
    }
    for rgb in test_colors
    {
        xyz := srgb_to_xyz(srgbu8_to_srgb(rgb))
        spoly, err := xyz_d65_to_spoly(xyz)

        xyz_or_spoly := spoly_to_xyz_d65(spoly)
        testing.expectf(
            t, linalg.length(xyz_or_spoly - xyz) < 1e-3,
            "expected error less than 1e-3 error was %.8f, targe rgb = (%i, %i, %i), target_xyz = (%.6f, %.6f, %.6f), spoly_xyz = (%.6f, %.6f, %.6f)",
            linalg.length(xyz_or_spoly - xyz), rgb.x, rgb.y, rgb.z, xyz.x, xyz.y, xyz.z, xyz_or_spoly.x, xyz_or_spoly.y, xyz_or_spoly.z
        )
    }
}

@(test)
approximate_spoly_color_test :: proc(t: ^testing.T)
{
    test_colors := []SRGBU8Color{
        SRGBU8Color{255, 255, 255},
        SRGBU8Color{0, 255, 255},
        SRGBU8Color{0, 0, 255},
        SRGBU8Color{0, 0, 0},
        SRGBU8Color{34, 167, 89},
    }
    for rgb in test_colors
    {
        xyz := srgb_to_xyz(srgbu8_to_srgb(rgb))
        spoly, err := approximate_xyz_d65_to_spoly(xyz)

        xyz_or_spoly := approximate_spoly_to_xyz_d65(spoly)
        testing.expectf(
            t, linalg.length(xyz_or_spoly - xyz) < 1e-3,
            "expected error less than 1e-3 error was %.8f, targe rgb = (%i, %i, %i), target_xyz = (%.6f, %.6f, %.6f), spoly_xyz = (%.6f, %.6f, %.6f)",
            linalg.length(xyz_or_spoly - xyz), rgb.x, rgb.y, rgb.z, xyz.x, xyz.y, xyz.z, xyz_or_spoly.x, xyz_or_spoly.y, xyz_or_spoly.z
        )
    }
}
