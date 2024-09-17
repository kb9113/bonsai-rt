slangc ./integrators/nee.slang -g -profile glsl_450 -target spirv -o ./_spirv/nee.spv -entry main
slangc ./blend_frames.slang -g -profile glsl_450 -target spirv -o ./_spirv/blend_frames.spv -entry main
