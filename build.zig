const std = @import("std");
const v8_build = @import("build/v8.build.zig");
const binding_build = @import("build/binding.build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const v8 = v8_build.add(b, target, optimize);

    const module = b.addModule("v8", .{
        .root_source_file = b.path("src/v8.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    linkSystem(module);
    module.addObjectFile(v8.lib);

    binding_build.addGenStep(b, target, optimize, v8.lib, linkSystem);

    // `zig build` installs the static library for non-Zig consumers.
    b.getInstallStep().dependOn(&b.addInstallFile(v8.lib, "libv8_zig.a").step);

    const tests = b.addTest(.{ .root_module = module });
    b.step("test", "Run library tests").dependOn(&b.addRunArtifact(tests).step);

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
    linkSystem(shell.root_module);
    shell.root_module.addObjectFile(v8.lib);
    const run_shell = b.addRunArtifact(shell);
    run_shell.addPassthruArgs();
    b.step("shell", "Run the demo JS REPL").dependOn(&run_shell.step);
}

/// V8 needs CoreFoundation (abseil) and Security (partition allocator) on macOS.
fn linkSystem(m: *std.Build.Module) void {
    if (m.resolved_target.?.result.os.tag == .macos) {
        m.addSystemFrameworkPath(.{ .cwd_relative = "/System/Library/Frameworks" });
        m.linkFramework("CoreFoundation", .{});
        m.linkFramework("Security", .{});
    }
}
