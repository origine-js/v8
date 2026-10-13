//! `zig build gen`: regenerates `src/binding.zig`, `binding/layout.gen.h` (from
//! `build-tools/layout.zon`) and `src/externs.gen.zig` (from binding.cc, with
//! `build-tools/typemap.zon` overrides) by asking V8's clang about the real
//! V8 configuration.
//! The generated files are committed; run this after changing the manifest or
//! upgrading V8 (the static_asserts in layout.gen.h fail the C++ build when stale).

const std = @import("std");
const v8_build = @import("v8.build.zig");

pub fn addGenStep(b: *std.Build, v8: v8_build.V8) void {
    const gen = b.step("gen", "Regenerate src/binding.zig, binding/layout.gen.h and src/externs.gen.zig");

    const build_dir = v8.build_dir orelse {
        gen.dependOn(&b.addFail("`zig build gen` needs a V8 build tree; do not pass -Dprebuilt_v8_path").step);
        return;
    };

    const tool = b.addExecutable(.{
        .name = "bindgen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/bindgen/main.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });

    const run = b.addRunArtifact(tool);
    run.addArg("gen");
    run.addArg(build_dir);
    run.addArg(rootPath(b, "build-tools/layout.zon"));
    run.addArg(rootPath(b, "build-tools/typemap.zon"));
    run.addArg(rootPath(b, "src/binding.zig"));
    run.addArg(rootPath(b, "binding/layout.gen.h"));
    run.addArg(rootPath(b, "src/externs.gen.zig"));
    // Writes into the source tree, so it must always run.
    run.has_side_effects = true;
    run.step.dependOn(v8.gn_step.?);
    gen.dependOn(&run.step);
}

fn rootPath(b: *std.Build, sub_path: []const u8) []const u8 {
    return b.root.joinString(b.allocator, sub_path) catch @panic("OOM");
}
