const std = @import("std");

/// Creates a build-owned static mimalloc library from the pinned dependency.
/// Links only mi_* APIs; libc symbols and macOS malloc zones are not overridden.
/// Returned artifact and dependency paths remain owned by b through the build.
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const source = b.dependency("mimalloc", .{});
    const module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true, .pic = true });
    module.addIncludePath(source.path("include"));
    module.addCSourceFile(.{
        .file = source.path("src/static.c"),
        .flags = &.{ "-std=c11", "-DMI_STATIC_LIB", "-DMI_OSX_ZONE=0", "-DMI_OSX_INTERPOSE=0" },
    });
    if (target.result.os.tag == .windows) {
        for ([_][]const u8{ "psapi", "shell32", "user32", "advapi32", "bcrypt" }) |name| module.linkSystemLibrary(name, .{});
    } else if (target.result.os.tag == .linux) {
        module.linkSystemLibrary("pthread", .{});
    }
    return b.addLibrary(.{ .name = "mimalloc", .linkage = .static, .root_module = module });
}
