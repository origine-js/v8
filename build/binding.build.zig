const std = @import("std");
const v8_pkg = @import("v8.build.zig");

pub const GenBindingResult = struct {
    path: std.Build.LazyPath,
    step: *std.Build.Step,
};

pub fn generateBinding(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    v8_build: v8_pkg.V8Build,
) !GenBindingResult {
    // 1. Create a tool to generate the sizes
    const gen_sizes_tool = b.addExecutable(.{
        .name = "gen_sizes",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen_binds.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link the generator tool against the built v8 library so it can resolve the SIZEOF symbols
    gen_sizes_tool.addObjectFile(v8_build.lib);
    gen_sizes_tool.addIncludePath(v8_build.include_path);
    gen_sizes_tool.addIncludePath(b.path("binding"));

    // V8 dependencies
    gen_sizes_tool.root_module.link_libc = true;
    gen_sizes_tool.root_module.link_libcpp = true;

    if (target.result.os.tag == .macos) {
        gen_sizes_tool.addSystemFrameworkPath(.{ .cwd_relative = "/System/Library/Frameworks" });
        gen_sizes_tool.linkFramework("CoreFoundation");
        gen_sizes_tool.linkFramework("Security");
    }

    // 2. Run the tool and capture output
    const run_gen = b.addRunArtifact(gen_sizes_tool);

    // 3. Capture stdout to a file
    const generated_file = run_gen.captureStdOut(.{});

    return .{
        .path = generated_file,
        .step = &run_gen.step,
    };
}
