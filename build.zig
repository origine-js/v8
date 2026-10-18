const std = @import("std");
const v8_build = @import("build/v8.build.zig");
const binding_build = @import("build/binding.build.zig");
const mimalloc_build = @import("build/mimalloc.build.zig");
const rusty_build = @import("build/rusty.build.zig");

/// Configures build-owned V8/mimalloc artifacts and modules; retains no runtime state.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const link_native = b.option(bool, "link_native", "Link native libraries into exported modules; disable for an external final link") orelse true;
    // Zig requires LLD for LTO, but its LLD integration cannot link Mach-O.
    const enable_lto = optimize != .debug and !target.result.os.tag.isDarwin();

    // V8 is built in release mode regardless of the Zig optimize mode: it is by far the slowest
    // part of the build and a debug V8 makes everything that embeds it slow. Opt into a debug V8
    // (faster incremental compiles, DCHECKs) only while changing V8 or its patches.
    const v8_debug = b.option(bool, "v8_debug", "Build V8 in debug mode for quick iteration on V8 patches (default: release V8)") orelse false;
    const v8 = v8_build.add(b, target, if (v8_debug) .debug else .fast);
    const clang_override = b.option([]const u8, "v8_clang_dir", "Matching V8 LLVM bin directory") orelse "";
    const clang_bin = if (clang_override.len != 0) clang_override else v8.clang_bin orelse
        (b.root.joinString(b.allocator, b.fmt(".lp-cache/v8-{s}/third_party/llvm-build/Release+Asserts/bin", .{v8_build.version})) catch @panic("OOM"));
    b.addNamedLazyPath("v8", v8.lib);
    b.addNamedLazyPath("v8_no_temporal", v8.lib_no_temporal);
    b.addNamedLazyPath("clang_bin", .{ .cwd_relative = clang_bin });
    var link_lib = v8.lib;
    if (link_native and target.result.os.tag == .macos) {
        const native = b.addSystemCommand(&.{ "uv", "run", "--script" });
        native.addFileArg(b.path("build-tools/scripts/native-archive.py"));
        native.addFileArg(v8.lib);
        link_lib = native.addOutputFileArg("libv8_zig.a");
        native.addArg(clang_bin);
        native.addArgs(&.{ "--target", b.fmt("{s}-apple-macos{f}", .{ @tagName(target.result.cpu.arch), target.result.os.version_range.semver.min }) });
    }
    const mimalloc = mimalloc_build.add(b, target, if (optimize == .debug) .fast else .safe);
    if (optimize != .debug) {
        mimalloc.use_llvm = true;
        if (enable_lto) {
            mimalloc.use_lld = true;
            mimalloc.lto = .full;
        }
    }

    const module = b.addModule("@v8", .{
        .root_source_file = b.path("src/v8.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = link_native,
    });
    if (link_native) {
        module.addObjectFile(link_lib);
        module.linkLibrary(mimalloc);
    }

    const util_module = b.addModule("@util", .{
        .root_source_file = b.path("src/eu.zig"),
        .target = target,
        .optimize = optimize,
    });
    util_module.addImport("@v8", module);

    _ = b.addModule("@diagnostics", .{
        .root_source_file = b.path("src/diagnostics.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const mimalloc_module = b.addModule("@mimalloc", .{
        .root_source_file = b.path("src/memory/mimalloc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (link_native) mimalloc_module.linkLibrary(mimalloc);
    util_module.addImport("@mimalloc", mimalloc_module);

    // Inspect the same native archive the wrappers link on macOS. System nm
    // cannot read the newer LLVM bitcode in V8's raw ThinLTO archive.
    rusty_build.addSteps(b, v8, mimalloc);
    var binding_v8 = v8;
    binding_v8.lib = link_lib;
    binding_build.addSteps(b, binding_v8);

    // `zig build` installs the static library for non-Zig consumers.
    b.getInstallStep().dependOn(&b.addInstallFile(v8.lib, "libv8_zig.a").step);
    b.installArtifact(mimalloc);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("@v8", module);
    test_module.addImport("@mimalloc", mimalloc_module);
    test_module.addImport("@util", util_module);
    const tests = b.addTest(.{ .root_module = test_module });
    if (optimize != .debug) {
        tests.use_llvm = true;
        if (enable_lto) {
            tests.use_lld = true;
            tests.lto = .full;
        }
    }
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // A separate process is required to inspect ICU before any test uses Intl.
    const lazy_icu_module = b.createModule(.{
        .root_source_file = b.path("src/tests/icu_lazy.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    lazy_icu_module.addImport("@v8", module);
    const lazy_icu_test = b.addTest(.{
        .root_module = lazy_icu_module,
        .filters = &.{"ICU: initialization and plain JS"},
    });
    if (optimize != .debug) {
        lazy_icu_test.use_llvm = true;
        if (enable_lto) {
            lazy_icu_test.use_lld = true;
            lazy_icu_test.lto = .full;
        }
    }
    const run_lazy_icu_test = b.addRunArtifact(lazy_icu_test);
    test_step.dependOn(&run_lazy_icu_test.step);
    b.step("test-icu-lazy", "Verify deferred ICU loading in a fresh process").dependOn(&run_lazy_icu_test.step);

    // The forged-property regression needs an unfrozen construction context.
    // Its flags are set before initialization in a separate test process.
    const native_stack_module = b.createModule(.{
        .root_source_file = b.path("src/tests/native_stack.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    native_stack_module.addImport("@v8", module);
    const native_stack_test = b.addTest(.{ .root_module = native_stack_module });
    if (optimize != .debug) {
        native_stack_test.use_llvm = true;
        if (enable_lto) {
            native_stack_test.use_lld = true;
            native_stack_test.lto = .full;
        }
    }
    test_step.dependOn(&b.addRunArtifact(native_stack_test).step);
}
