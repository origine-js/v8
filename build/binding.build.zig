//! Steps backed by `tools/bindgen`:
//!
//!   zig build gen             regenerate src/binding.zig, binding/layout.gen.h and
//!                             src/externs.gen.zig (committed outputs)
//!   zig build check-generated fail if the committed outputs differ from fresh ones
//!   zig build check-bindings  library symbols vs externs.gen.zig (hard check), plus a
//!                             report of unwrapped shims and what rusty_v8 has that we lack
//!
//! All of them ask V8's own clang / the built library about the real configuration.
//! Run `gen` after changing the manifests, binding.cc or upgrading V8 (the
//! static_asserts in layout.gen.h fail the C++ build when stale).

const std = @import("std");
const v8_build = @import("v8.build.zig");

pub fn addSteps(b: *std.Build, v8: v8_build.V8) void {
    const gen = b.step("gen", "Regenerate src/binding.zig, binding/layout.gen.h and src/externs.gen.zig");
    const check_generated = b.step("check-generated", "Fail if the committed generated files are stale");
    const check_bindings = b.step("check-bindings", "Compare the library, externs.gen.zig, v8.zig and rusty_v8");

    const tool = b.addExecutable(.{
        .name = "bindgen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/bindgen/main.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });

    // check-bindings only needs the built library, so it also works with -Dprebuilt_v8_path.
    {
        const run = b.addRunArtifact(tool);
        run.addArg("check");
        run.addFileArg(v8.lib);
        run.addFileArg(b.path("src/externs.gen.zig"));
        run.addFileArg(b.path("src/v8.zig"));
        if (b.lazyDependency("rusty_v8", .{})) |rusty| run.addFileArg(rusty.path("src/binding.cc"));
        check_bindings.dependOn(&run.step);
    }

    const build_dir = v8.build_dir orelse {
        const msg = "this step needs a V8 build tree; do not pass -Dprebuilt_v8_path";
        gen.dependOn(&b.addFail(msg).step);
        check_generated.dependOn(&b.addFail(msg).step);
        return;
    };

    for ([_]struct { []const u8, *std.Build.Step }{ .{ "gen", gen }, .{ "gen-check", check_generated } }) |mode| {
        const run = b.addRunArtifact(tool);
        run.addArg(mode[0]);
        run.addArg(build_dir);
        run.addArg(rootPath(b, "build-tools/layout.zon"));
        run.addArg(rootPath(b, "build-tools/typemap.zon"));
        run.addArg(rootPath(b, "src/binding.zig"));
        run.addArg(rootPath(b, "binding/layout.gen.h"));
        run.addArg(rootPath(b, "src/externs.gen.zig"));
        // `gen` writes into the source tree and both read it: always run.
        run.has_side_effects = true;
        run.step.dependOn(v8.gn_step.?);
        mode[1].dependOn(&run.step);
    }
}

fn rootPath(b: *std.Build, sub_path: []const u8) []const u8 {
    return b.root.joinString(b.allocator, sub_path) catch @panic("OOM");
}
