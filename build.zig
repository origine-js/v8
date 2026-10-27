const std = @import("std");
const v8_build = @import("build/v8.build.zig");
const binding_build = @import("build/binding.build.zig");
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
    // For a Rust consumer of the `v8` crate (rusty_v8 build.rs): the checkout, the shim sources and the
    // GN compile commands that select V8's ABI. Absent for a prebuilt archive, which has no GN output.
    b.addNamedLazyPath("binding", b.path("binding"));
    if (v8.build_dir) |build_dir| {
        b.addNamedLazyPath("v8_root", .{ .cwd_relative = std.fs.path.dirname(std.fs.path.dirname(build_dir).?).? });
        const commands = b.fmt("{s}/compile_commands.json", .{build_dir});
        const have_commands = if (std.Io.Dir.accessAbsolute(b.graph.io, commands, .{})) |_| true else |_| false;
        if (have_commands) {
            b.addNamedLazyPath("gn_compile_commands", .{ .cwd_relative = commands });
        } else {
            // First build: GN has not run yet; copy its output once it has.
            const copy = b.addSystemCommand(&.{"cp"});
            copy.addArg(commands);
            b.addNamedLazyPath("gn_compile_commands", copy.addOutputFileArg("compile_commands.json"));
            copy.step.dependOn(v8.gn_step.?);
        }
    }
    var link_lib = v8.lib;
    if (link_native and target.result.os.tag == .macos) {
        const native = b.addSystemCommand(&.{ "uv", "run", "--script" });
        native.addFileArg(b.path("build-tools/scripts/native-archive.py"));
        native.addFileArg(v8.lib);
        link_lib = native.addOutputFileArg("libv8_zig.a");
        native.addArg(clang_bin);
        native.addArgs(&.{ "--target", b.fmt("{s}-apple-macos{f}", .{ @tagName(target.result.cpu.arch), target.result.os.version_range.semver.min }) });
    }
    const mimalloc_dep = b.dependency("mimalloc", .{
        .target = target,
        .optimize = if (optimize == .debug) std.builtin.OptimizeMode.fast else .safe,
        .lto = enable_lto,
    });
    const mimalloc = mimalloc_dep.artifact("mimalloc");

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
        if (v8.icu) |icu| module.linkLibrary(icu);
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
    // Re-exported so dependents (the root build) take `@mimalloc` from here with `@v8`.
    const mimalloc_module = mimalloc_dep.module("@mimalloc");
    b.modules.put(b.graph.arena, b.dupe("@mimalloc"), mimalloc_module) catch @panic("OOM");
    if (link_native) mimalloc_module.linkLibrary(mimalloc);
    util_module.addImport("@mimalloc", mimalloc_module);
    module.addImport("@mimalloc", mimalloc_module);

    // Inspect the same native archive the wrappers link on macOS. System nm
    // cannot read the newer LLVM bitcode in V8's raw ThinLTO archive.
    rusty_build.addSteps(b, v8, mimalloc);
    var binding_v8 = v8;
    binding_v8.lib = link_lib;
    binding_build.addSteps(b, binding_v8);

    // `zig build` installs the static library for non-Zig consumers.
    b.getInstallStep().dependOn(&b.addInstallFile(v8.lib, "libv8_zig.a").step);
    b.installArtifact(mimalloc);
    // The ICU provider is a separate link object; an external final link takes it from here.
    if (v8.icu) |icu| b.installArtifact(icu);

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

    if (v8.icu_mode == .compressed) {
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
    }

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
