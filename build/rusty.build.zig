//! `zig build rusty` / `zig build test-rusty`: build and test lib/rusty_v8 (the Rust `v8`
//! crate) against the same `libv8_zig.a` the Zig modules use, so both languages share one V8.

const std = @import("std");
const v8_build = @import("v8.build.zig");

/// Adds the cargo-backed steps. Borrows `v8` and `mimalloc` descriptions for graph
/// construction; the steps run cargo in the vendored crate, which owns its `target/`
/// directory. No-op for prebuilt V8 (`-Dprebuilt_v8_path`), which lacks a GN output.
pub fn addSteps(b: *std.Build, v8: v8_build.V8, mimalloc: *std.Build.Step.Compile) void {
    const build_dir = v8.build_dir orelse return;
    const clang_bin = v8.clang_bin orelse return;
    const crate_dir = b.option([]const u8, "rusty_v8_dir", "Vendored rusty_v8 crate (default ../rusty_v8)") orelse
        b.root.joinString(b.allocator, "../rusty_v8") catch @panic("OOM");
    const extra_args = b.option([]const u8, "rusty_cargo_args", "Extra space-separated cargo arguments for the rusty steps") orelse "";
    // build_dir is <v8 root>/out/<name>.
    const v8_root = std.fs.path.dirname(std.fs.path.dirname(build_dir).?).?;

    const names = [_]struct { step: []const u8, desc: []const u8, args: []const []const u8 }{
        .{ .step = "rusty", .desc = "Build lib/rusty_v8 against libv8_zig.a", .args = &.{ "build", "--release" } },
        .{ .step = "test-rusty", .desc = "Run lib/rusty_v8 tests against libv8_zig.a", .args = &.{ "test", "--release" } },
    };
    for (names) |n| {
        const run = b.addSystemCommand(&.{"sh"});
        run.addFileArg(b.path("build-tools/scripts/cargo-rusty.sh"));
        run.addArg(crate_dir);
        run.addFileArg(v8.lib_no_temporal);
        run.addFileArg(mimalloc.getEmittedBin());
        run.addArgs(&.{ v8_root, build_dir, b.root.joinString(b.allocator, "binding") catch @panic("OOM"), clang_bin });
        run.addArgs(n.args);
        if (extra_args.len != 0) {
            var it = std.mem.tokenizeScalar(u8, extra_args, ' ');
            while (it.next()) |arg| run.addArg(arg);
        }
        run.has_side_effects = true;
        if (v8.gn_step) |gn| run.step.dependOn(gn);
        b.step(n.step, n.desc).dependOn(&run.step);
    }
}
