const std = @import("std");

const V8_VERSION: []const u8 = "14.5.201.4";

const LazyPath = std.Build.LazyPath;

pub const V8Build = struct {
    lib: LazyPath,
    include_path: LazyPath,
    step: *std.Build.Step,
};

fn mapArch(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.cpu.arch) {
        .aarch64 => "arm64",
        .arm => "arm",
        .riscv64 => "riscv64",
        .x86_64 => "x64",
        .x86 => "x86",
        else => |x| @tagName(x),
    };
}

fn mapOs(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        .linux => "linux",
        .macos => "mac",
        .ios => "ios",
        .fuchsia => "fuchsia",
        else => @panic("os may not be supported"),
    };
}

pub fn buildV8(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !V8Build {
    const cache_root = b.option([]const u8, "cache_root", "Root directory for the V8 and depot_tools cache") orelse b.pathFromRoot(".lp-cache");

    // Ensure cache root exists
    std.fs.cwd().makeDir(cache_root) catch {};

    const v8_dir = b.fmt("{s}/v8-{s}", .{ cache_root, V8_VERSION });
    const depot_tools_dir = b.fmt("{s}/depot_tools-{s}", .{ cache_root, V8_VERSION });

    const bootstrapped_depot_tools = try bootstrapDepotTools(b, depot_tools_dir);
    const bootstrapped_v8 = try bootstrapV8(b, bootstrapped_depot_tools, v8_dir, depot_tools_dir);

    const v8_dir_lazy_path: LazyPath = .{ .cwd_relative = v8_dir };
    const allocator = b.allocator;

    const tag = target.result.os.tag;
    const arch = target.result.cpu.arch;

    var gn_args: std.Io.Writer.Allocating = .init(allocator);
    defer gn_args.deinit();

    try gn_args.writer.print("target_os=\"{s}\"\n", .{mapOs(target)});
    try gn_args.writer.print("target_cpu=\"{s}\"\n", .{mapArch(target)});
    try gn_args.writer.print("v8_target_cpu=\"{s}\"\n", .{mapArch(target)});
    try gn_args.writer.writeAll("is_official_build=false\n");
    switch (optimize) {
        .Debug => {
            try gn_args.writer.writeAll("is_debug=true\n");
            try gn_args.writer.writeAll("symbol_level=1\n");
        },
        .ReleaseSafe => {
            try gn_args.writer.writeAll("is_debug=false\n");
            try gn_args.writer.writeAll("v8_optimized_debug=true\n");
            try gn_args.writer.writeAll("symbol_level=1\n");
        },
        .ReleaseFast, .ReleaseSmall => {
            try gn_args.writer.writeAll("is_debug=false\n");
            try gn_args.writer.writeAll("symbol_level=0\n");
        },
    }

    switch (tag) {
        .ios => {
            try gn_args.writer.writeAll("v8_enable_pointer_compression=false\n");
            try gn_args.writer.writeAll("v8_enable_webassembly=false\n");
        },
        .linux => {
            if (arch == .aarch64) {
                try gn_args.writer.writeAll("clang_base_path=\"/usr/lib/llvm-21\"\n");
                try gn_args.writer.writeAll("clang_use_chrome_plugins=false\n");
                try gn_args.writer.writeAll("treat_warnings_as_errors=false\n");
            }
        },
        else => {},
    }

    const out_dir = b.fmt("out/{s}/{s}", .{ @tagName(tag), @tagName(optimize) });

    const gn_run = b.addSystemCommand(&.{
        getDepotToolExePath(b, depot_tools_dir, "gn"),
        "--root=.",
        "--root-target=//zig",
        "--dotfile=zig/.gn",
        "gen",
        out_dir,
        b.fmt("--args={s}", .{gn_args.toOwnedSlice() catch @panic("OOM")}),
    });
    gn_run.setCwd(v8_dir_lazy_path);
    addDepotToolsToPath(gn_run, depot_tools_dir);
    gn_run.step.dependOn(&bootstrapped_v8.step);

    const ninja_run = b.addSystemCommand(&.{
        getDepotToolExePath(b, depot_tools_dir, "ninja"),
        "-C",
        out_dir,
        "v8_zig",
    });
    ninja_run.setCwd(v8_dir_lazy_path);
    addDepotToolsToPath(ninja_run, depot_tools_dir);
    ninja_run.step.dependOn(&gn_run.step);

    const lib_path = b.fmt("{s}/obj/zig/libv8_zig.a", .{out_dir});

    // Use addWriteFiles to ensure the library is correctly brought into the Zig build graph
    const wf = b.addWriteFiles();
    wf.step.dependOn(&ninja_run.step);
    const lib_file = wf.addCopyFile(v8_dir_lazy_path.path(b, lib_path), "libv8_zig.a");

    return V8Build{
        .lib = lib_file,
        .include_path = v8_dir_lazy_path.path(b, "include"),
        .step = &wf.step,
    };
}

fn getDepotToolExePath(b: *std.Build, depot_tools_dir: []const u8, executable: []const u8) []const u8 {
    return b.fmt("{s}/{s}", .{ depot_tools_dir, executable });
}

fn addDepotToolsToPath(step: *std.Build.Step.Run, depot_tools_dir: []const u8) void {
    step.addPathDir(depot_tools_dir);
}

fn bootstrapDepotTools(b: *std.Build, depot_tools_dir: []const u8) !*std.Build.Step.Run {
    const depot_tools = b.dependency("depot_tools", .{});
    const marker_file = b.fmt("{s}/.bootstrap-complete", .{depot_tools_dir});

    const needs_full_bootstrap = blk: {
        std.fs.cwd().access(marker_file, .{}) catch break :blk true;
        break :blk false;
    };

    if (!needs_full_bootstrap) return b.addSystemCommand(&.{"true"});

    const copy_depot_tools = b.addSystemCommand(&.{ "cp", "-r" });
    copy_depot_tools.addDirectoryArg(depot_tools.path(""));
    copy_depot_tools.addArg(depot_tools_dir);

    const ensure_bootstrap = b.addSystemCommand(&.{
        getDepotToolExePath(b, depot_tools_dir, "ensure_bootstrap"),
    });
    ensure_bootstrap.setCwd(.{ .cwd_relative = depot_tools_dir });
    addDepotToolsToPath(ensure_bootstrap, depot_tools_dir);
    ensure_bootstrap.step.dependOn(&copy_depot_tools.step);

    const create_marker = b.addSystemCommand(&.{ "touch", marker_file });
    create_marker.step.dependOn(&ensure_bootstrap.step);

    return create_marker;
}

fn bootstrapV8(
    b: *std.Build,
    bootstrapped_depot_tools: *std.Build.Step.Run,
    v8_dir: []const u8,
    depot_tools_dir: []const u8,
) !*std.Build.Step.Run {
    const marker_file = b.fmt("{s}/.bootstrap-complete", .{v8_dir});

    const needs_full_bootstrap = blk: {
        std.fs.cwd().access(marker_file, .{}) catch break :blk true;
        break :blk false;
    };

    if (!needs_full_bootstrap) {
        const needs_source_update = blk: {
            const marker_stat = std.fs.cwd().statFile(marker_file) catch break :blk true;
            const marker_mtime = marker_stat.mtime;

            const source_dirs = [_][]const u8{
                b.pathFromRoot("binding"),
                b.pathFromRoot("build-tools"),
            };

            for (source_dirs) |dir_path| {
                var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch continue;
                defer dir.close();

                var walker = dir.walk(b.allocator) catch continue;
                defer walker.deinit();
                while (walker.next() catch continue) |entry| {
                    if (entry.kind == .file) {
                        const stat = entry.dir.statFile(entry.path) catch continue;
                        if (stat.mtime.toNanoseconds() > marker_mtime.toNanoseconds()) break :blk true;
                    }
                }
            }
            break :blk false;
        };

        if (needs_source_update) {
            std.debug.print("Updating source files in V8 bootstrap\n", .{});
            const zig_dir = b.fmt("{s}/zig", .{v8_dir});
            const rm_zig = b.addSystemCommand(&.{ "rm", "-rf", zig_dir });
            const mkdir_zig = b.addSystemCommand(&.{ "mkdir", "-p", zig_dir });
            mkdir_zig.step.dependOn(&rm_zig.step);

            const copy_binding = b.addSystemCommand(&.{ "cp", "-r" });
            copy_binding.addDirectoryArg(b.path("binding/"));
            copy_binding.addArg(b.fmt("{s}/zig/", .{v8_dir}));
            copy_binding.step.dependOn(&mkdir_zig.step);

            const copy_build_gn = b.addSystemCommand(&.{"cp"});
            copy_build_gn.addFileArg(b.path("build-tools/BUILD.gn"));
            copy_build_gn.addArg(b.fmt("{s}/zig/BUILD.gn", .{v8_dir}));
            copy_build_gn.step.addWatchInput(b.path("build-tools/BUILD.gn")) catch unreachable;
            copy_build_gn.step.dependOn(&mkdir_zig.step);

            const copy_gn = b.addSystemCommand(&.{"cp"});
            copy_gn.addFileArg(b.path("build-tools/.gn"));
            copy_gn.addArg(b.fmt("{s}/zig/.gn", .{v8_dir}));
            copy_gn.step.addWatchInput(b.path("build-tools/.gn")) catch unreachable;
            copy_gn.step.dependOn(&mkdir_zig.step);

            const update_marker = b.addSystemCommand(&.{ "touch", marker_file });
            update_marker.step.dependOn(&copy_binding.step);
            update_marker.step.dependOn(&copy_build_gn.step);
            update_marker.step.dependOn(&copy_gn.step);

            return update_marker;
        }

        return b.addSystemCommand(&.{"true"});
    }

    const mkdir = b.addSystemCommand(&.{ "mkdir", "-p", v8_dir });
    mkdir.step.dependOn(&bootstrapped_depot_tools.step);

    const gclient_content = b.fmt(
        \\solutions = [
        \\  {{
        \\    "name": ".",
        \\    "url": "https://chromium.googlesource.com/v8/v8.git@{s}",
        \\    "deps_file": "DEPS",
        \\    "managed": False,
        \\    "custom_deps": {{}},
        \\  }},
        \\]
        \\
    , .{V8_VERSION});

    const write_gclient = b.addSystemCommand(&.{ "sh", "-c" });
    write_gclient.addArg(b.fmt("echo '{s}' > {s}/.gclient", .{ gclient_content, v8_dir }));
    write_gclient.step.dependOn(&mkdir.step);

    const zig_dir = b.fmt("{s}/zig", .{v8_dir});
    const mkdir_zig = b.addSystemCommand(&.{ "mkdir", "-p", zig_dir });
    mkdir_zig.step.dependOn(&write_gclient.step);

    const copy_binding = b.addSystemCommand(&.{ "cp", "-r" });
    copy_binding.addDirectoryArg(b.path("binding/"));
    copy_binding.addArg(b.fmt("{s}/zig/", .{v8_dir}));
    copy_binding.step.dependOn(&mkdir_zig.step);

    const copy_build_gn = b.addSystemCommand(&.{"cp"});
    copy_build_gn.addFileArg(b.path("build-tools/BUILD.gn"));
    copy_build_gn.addArg(b.fmt("{s}/zig/BUILD.gn", .{v8_dir}));
    copy_build_gn.step.dependOn(&mkdir_zig.step);

    const copy_gn = b.addSystemCommand(&.{"cp"});
    copy_gn.addFileArg(b.path("build-tools/.gn"));
    copy_gn.addArg(b.fmt("{s}/zig/.gn", .{v8_dir}));
    copy_gn.step.dependOn(&mkdir_zig.step);

    const gclient_sync = b.addSystemCommand(&.{
        getDepotToolExePath(b, depot_tools_dir, "gclient"),
        "sync",
    });
    gclient_sync.setCwd(.{ .cwd_relative = v8_dir });
    addDepotToolsToPath(gclient_sync, depot_tools_dir);
    gclient_sync.step.dependOn(&copy_build_gn.step);
    gclient_sync.step.dependOn(&copy_gn.step);

    const clang_update = b.addSystemCommand(&.{
        getDepotToolExePath(b, depot_tools_dir, "python-bin/python3"),
        "tools/clang/scripts/update.py",
    });
    clang_update.setCwd(.{ .cwd_relative = v8_dir });
    addDepotToolsToPath(clang_update, depot_tools_dir);
    clang_update.step.dependOn(&gclient_sync.step);

    const create_marker = b.addSystemCommand(&.{ "touch", marker_file });
    create_marker.step.dependOn(&clang_update.step);

    return create_marker;
}
