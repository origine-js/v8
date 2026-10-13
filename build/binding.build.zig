//! `zig build gen`: regenerates the struct-size constants from the built V8 library.
//!
//! The result goes to `zig-out/binding.zig` instead of overwriting `src/binding.zig`:
//! the committed file carries entries (e.g. `FunctionCallbackInfo`, `consts`) that
//! `tools/gen_binds.zig` does not produce yet, so merge by hand.

const std = @import("std");

pub fn addGenStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    v8_lib: std.Build.LazyPath,
    link_system: *const fn (*std.Build.Module) void,
) void {
    const tool = b.addExecutable(.{
        .name = "gen_binds",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen_binds.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    tool.root_module.addObjectFile(v8_lib);
    link_system(tool.root_module);

    const run = b.addRunArtifact(tool);
    const generated = run.captureStdOut(.{});

    const install = b.addInstallFile(generated, "binding.zig");
    b.step("gen", "Generate binding sizes into zig-out/binding.zig").dependOn(&install.step);
}
