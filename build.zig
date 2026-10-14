const std = @import("std");
const v8_build = @import("build/v8.build.zig");
const binding_build = @import("build/binding.build.zig");
const mimalloc_build = @import("build/mimalloc.build.zig");

/// Configures build-owned V8/mimalloc artifacts and modules; retains no runtime state.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Zig requires LLD for LTO, but its LLD integration cannot link Mach-O.
    const enable_lto = optimize != .debug and !target.result.os.tag.isDarwin();

    const v8 = v8_build.add(b, target, if (optimize == .debug) .debug else .fast);
    const mimalloc = mimalloc_build.add(b, target, if (optimize == .debug) .fast else .safe);
    if (optimize != .debug) {
        mimalloc.use_llvm = true;
        if (enable_lto) {
            mimalloc.use_lld = true;
            mimalloc.lto = .full;
        }
    }

    const module = b.addModule("v8", .{
        .root_source_file = b.path("src/v8.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    module.addObjectFile(v8.lib);
    module.linkLibrary(mimalloc);

    binding_build.addSteps(b, v8);

    // `zig build` installs the static library for non-Zig consumers.
    b.getInstallStep().dependOn(&b.addInstallFile(v8.lib, "libv8_zig.a").step);
    b.installArtifact(mimalloc);

    const tests = b.addTest(.{ .root_module = module });
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
        .root_source_file = b.path("src/icu_lazy_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    lazy_icu_module.addObjectFile(v8.lib);
    lazy_icu_module.linkLibrary(mimalloc);
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

    // Demo REPL.
    const shell = b.addExecutable(.{
        .name = "shell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shell.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    if (optimize != .debug) {
        shell.use_llvm = true;
        if (enable_lto) {
            shell.use_lld = true;
            shell.lto = .full;
        }
    }
    if (target.result.os.tag == .macos) {
        // Apple's Mach-O linker runs its identical-code deduplication pass by
        // default. Keep the native linker for shell so this stays enabled.
        shell.use_lld = false;
    }
    shell.root_module.addObjectFile(v8.lib);
    shell.root_module.linkLibrary(mimalloc);
    const run_shell = b.addRunArtifact(shell);
    run_shell.addPassthruArgs();
    b.step("shell", "Run the demo JS REPL").dependOn(&run_shell.step);
}

