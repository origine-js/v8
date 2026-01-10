const std = @import("std");
const v8_pkg = @import("build/v8.build.zig");
const binding_pkg = @import("build/binding.build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Build V8 and its C++ bindings
    const v8_build = try v8_pkg.buildV8(b, target, optimize);

    // 2. Generate the binding constants (sizes) from the built V8 binary
    const generated_binding = try binding_pkg.generateBinding(b, target, optimize, v8_build);

    const write_binding_files = b.addWriteFiles();
    write_binding_files.step.dependOn(generated_binding.step);
    _ = write_binding_files.addCopyFile(generated_binding.path, b.build_root.join(b.allocator, &.{ "src/", "binding.zig" }) catch @panic("OOM"));

    const step = b.step("gen", "Generate bindings");
    step.dependOn(generated_binding.step);
    step.dependOn(&write_binding_files.step);

    // 3. Create the module with the generated constants
    // The generated file will be available as "@import("$binding")" to our source code
    const v8_module = b.addModule("v8", .{
        .root_source_file = b.path("src/v8.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    // Add the generated file as a named import to the module
    v8_module.addImport("$binding", b.createModule(.{
        .root_source_file = generated_binding.path,
    }));

    v8_module.addObjectFile(v8_build.lib);
    v8_module.addIncludePath(v8_build.include_path);
    v8_module.addIncludePath(b.path("binding"));

    if (target.result.os.tag == .macos) {
        v8_module.addSystemFrameworkPath(.{ .cwd_relative = "/System/Library/Frameworks" });
        v8_module.linkFramework("CoreFoundation", .{});
        v8_module.linkFramework("Security", .{});
    }

    // 4. Install the library
    const install_lib = b.addInstallFile(v8_build.lib, "libv8_zig.a");
    b.getInstallStep().dependOn(&install_lib.step);

    // 5. Unit Tests
    const tests = b.addTest(.{
        .root_module = v8_module,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
