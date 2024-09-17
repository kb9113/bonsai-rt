# Color

A simple libary for color conversions between xyz color rgb color
and sigmoided polynomial spectral representaions as outlined in https://www.pbrt.org/.
However I use the actual jacobian for gauss newton optimization since it gives a smaller error to the target color. \
\
This libary also provides conversions based on approximate color match functions and whitepoint functions
which can be cheaper when you need to perform conversions back on the gpu.\
\
This libary is used by bonsai_rt my physically based renderer.


## Example converting to sigmoided polinomial representaiton and back again
```odin
xyz := srgb_to_xyz(srgbu8_to_srgb(SRGBU8Color{34, 167, 89}))
spoly, err := xyz_d65_to_spoly(xyz)

xyz_or_spoly := spoly_to_xyz_d65(spoly)
assert(linalg.length(xyz_or_spoly - xyz) < 1e-3)
```

## Example using approximations of the xyz color match functions and d65 white point
```odin
xyz := srgb_to_xyz(srgbu8_to_srgb(rgb))
spoly, err := approximate_xyz_d65_to_spoly(xyz)

xyz_or_spoly := approximate_spoly_to_xyz_d65(spoly)
assert(linalg.length(xyz_or_spoly - xyz) < 1e-3)
```
