package main
import "./geometry"
import "./acorn/resource"
import "./acorn/device"
import "./color"
import vk "vendor:vulkan"
import "base:runtime"
import "core:debug/trace"
import "./scene"
import "core:math/linalg"
import sdl "vendor:sdl2"
import "core:fmt"
import "core:time"
import "core:os"
import "core:flags"
import "./material_testing"

global_trace_ctx: trace.Context

debug_trace_assertion_failure_proc :: proc(prefix, message: string, loc := #caller_location) -> ! {
	runtime.print_caller_location(loc)
	runtime.print_string(" ")
	runtime.print_string(prefix)
	if len(message) > 0 {
		runtime.print_string(": ")
		runtime.print_string(message)
	}
	runtime.print_byte('\n')

	ctx := &global_trace_ctx
	if !trace.in_resolve(ctx) {
		buf: [64]trace.Frame
		runtime.print_string("Debug Trace:\n")
		frames := trace.frames(ctx, 1, buf[:])
		for f, i in frames {
			fl := trace.resolve(ctx, f, context.temp_allocator)
			if fl.loc.file_path == "" && fl.loc.line == 0 {
				continue
			}
			runtime.print_caller_location(fl.loc)
			runtime.print_string(" - frame ")
			runtime.print_int(i)
			runtime.print_byte('\n')
		}
	}
	runtime.trap()
}

main :: proc()
{
    trace.init(&global_trace_ctx)
   	defer trace.destroy(&global_trace_ctx)
   	context.assertion_failure_proc = debug_trace_assertion_failure_proc

    //material_testing.test_refract()

    if len(os.args) != 3
    {
        fmt.println("usage")
        fmt.println("bonsai_rt <scene.json> <out_img.png>")
        return
    }

    s := scene.read_scene(os.args[1])

    device_context := device.make_device(
        false,
        device.std_ray_trace_feature_set(),
        "bonsai_rt",
        i32(s.settings.width), i32(s.settings.height)
    )

    g := geometry.make_geometry(&device_context)
    geometry.load_scene(&device_context, &g, s)
    start_time := time.now()._nsec
    geometry.render(&device_context, &g)
    end_time := time.now()._nsec
    fmt.println(s.settings.n_samples, "samples in", (end_time - start_time) / 1_000_000, "ms")
    geometry.save_output_image_to_file(&device_context, &g, os.args[2])
}
