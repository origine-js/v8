//! Builds V8 plus our C++ shim (`binding/`) into a single static library.
//!
//! Pipeline: stage shims into the V8 tree -> fetch (depot_tools, gclient, clang)
//! -> `gn gen` -> `autoninja`. Every stage is idempotent, so the steps simply run
//! each time and defer to rsync/markers/ninja for incrementality.

const std = @import("std");
const zstd_build = @import("zstd.build.zig");

const LazyPath = std.Build.LazyPath;

pub const version = "14.7.173.20";

pub const V8 = struct {
    /// `libv8_zig.a`, a complete static library containing V8 and the shim.
    lib: LazyPath,
    /// GN output directory (holds compile_commands.json). Null for prebuilt libraries.
    build_dir: ?[]const u8 = null,
    /// Finishes once GN has generated `build_dir`. Null for prebuilt libraries.
    gn_step: ?*std.Build.Step = null,
};

/// Files copied into the V8 checkout. `src` is relative to this repository,
/// `dest` to the V8 source root.
const shims = [_]struct { src: []const u8, dest: []const u8 }{
    .{ .src = "binding/binding.cc", .dest = "zig/binding/binding.cc" },
    .{ .src = "binding/binding.hpp", .dest = "zig/binding/binding.hpp" },
    .{ .src = "binding/icu-compressed.cc", .dest = "zig/binding/icu-compressed.cc" },
    .{ .src = "binding/darwin-frameworks.cc", .dest = "zig/binding/darwin-frameworks.cc" },
    .{ .src = "binding/icu-compressed.h", .dest = "zig/binding/icu-compressed.h" },
    .{ .src = "binding/support.h", .dest = "zig/binding/support.h" },
    .{ .src = "binding/layout.gen.h", .dest = "zig/binding/layout.gen.h" },
    .{ .src = "build-tools/BUILD.gn", .dest = "zig/BUILD.gn" },
    .{ .src = "build-tools/.gn", .dest = "zig/.gn" },
};

const GnArgs = struct {
    is_debug: bool,
    symbol_level: u8,
    is_asan: bool,
    is_tsan: bool,
    v8_enable_sandbox: bool,
    /// Pass V8 handles as direct object addresses. This changes the C ABI, so
    /// `zig build gen` must be re-run after toggling it (src/binding.zig and
    /// binding/layout.gen.h record the configuration).
    v8_enable_direct_handle: bool,
    /// macOS SDK to compile against; GN picks the newest installed one when null.
    mac_sdk_path: ?[]const u8,

    /// Borrows self and target for this call; returns build-allocator-owned GN text
    /// valid until build teardown. Allocation failure panics; retains no inputs.
    fn render(self: GnArgs, b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
        var lines: std.ArrayList([]const u8) = .empty;
        const a = b.allocator;
        lines.append(a, b.fmt("target_os=\"{s}\"", .{gnOs(target)})) catch @panic("OOM");
        lines.append(a, b.fmt("target_cpu=\"{s}\"", .{gnCpu(target)})) catch @panic("OOM");
        lines.append(a, b.fmt("v8_target_cpu=\"{s}\"", .{gnCpu(target)})) catch @panic("OOM");
        lines.append(a, "use_siso=true") catch @panic("OOM");
        // Official builds depend on PGO.
        lines.append(a, "is_official_build=false") catch @panic("OOM");
        // Replace the raw linked ICU package with our compressed embedded copy.
        // mksnapshot still needs the uncompressed build-time data file.
        lines.appendSlice(a, &.{ "icu_use_data_file=true", "icu_use_stub_data=true" }) catch @panic("OOM");
        lines.append(a, b.fmt("is_debug={}", .{self.is_debug})) catch @panic("OOM");
        if (!self.is_debug) {
            lines.append(a, "is_clang=true") catch @panic("OOM");
            // Darwin consumers use Zig's Mach-O linker, which cannot consume LTO objects.
            lines.append(a, b.fmt("use_thin_lto={}", .{!target.result.os.tag.isDarwin()})) catch @panic("OOM");
        }
        lines.append(a, b.fmt("symbol_level={d}", .{self.symbol_level})) catch @panic("OOM");
        lines.append(a, b.fmt("is_asan={}", .{self.is_asan})) catch @panic("OOM");
        lines.append(a, b.fmt("is_tsan={}", .{self.is_tsan})) catch @panic("OOM");
        lines.append(a, b.fmt("v8_enable_sandbox={}", .{self.v8_enable_sandbox})) catch @panic("OOM");
        // Only spelled out when enabled so the default configuration keeps its build directory.
        if (self.v8_enable_direct_handle) lines.append(a, "v8_enable_direct_handle=true") catch @panic("OOM");

        if (self.mac_sdk_path) |path| {
            lines.append(a, b.fmt("mac_sdk_path=\"{s}\"", .{path})) catch @panic("OOM");
        }

        switch (target.result.os.tag) {
            .ios => lines.appendSlice(a, &.{
                "v8_enable_pointer_compression=false",
                "v8_enable_webassembly=false",
            }) catch @panic("OOM"),
            .linux => if (target.result.cpu.arch == .aarch64) lines.appendSlice(a, &.{
                "clang_base_path=\"/usr/lib/llvm-21\"",
                "clang_use_chrome_plugins=false",
                "treat_warnings_as_errors=false",
            }) catch @panic("OOM"),
            else => {},
        }
        return std.mem.join(a, "\n", lines.items) catch @panic("OOM");
    }
};

fn gnCpu(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x64",
        .x86 => "x86",
        .arm => "arm",
        .riscv64 => "riscv64",
        else => |arch| @tagName(arch),
    };
}

fn gnOs(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        .linux => "linux",
        .macos => "mac",
        .ios => "ios",
        .fuchsia => "fuchsia",
        else => @panic("unsupported target os"),
    };
}

/// Copies target's descriptor; borrows b and its target storage through build
/// teardown. Returns build-owned artifact paths
/// valid through build teardown. Build steps own generated compressed ICU bytes.
/// A prebuilt path is borrowed through build execution and must include its own
/// ICU initialization implementation. Configuration allocation failure panics.
pub fn add(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
) V8 {
    if (b.option([]const u8, "prebuilt_v8_path", "Path to a prebuilt libv8_zig.a; skips building V8")) |path| {
        return .{ .lib = .{ .cwd_relative = path } };
    }

    const gn_args: GnArgs = .{
        .is_debug = optimize == .debug,
        .symbol_level = b.option(u8, "symbol_level", "GN symbol_level") orelse if (optimize == .debug) 1 else 0,
        .is_asan = b.option(bool, "is_asan", "Build V8 with AddressSanitizer") orelse false,
        .is_tsan = b.option(bool, "is_tsan", "Build V8 with ThreadSanitizer") orelse false,
        .v8_enable_sandbox = b.option(bool, "v8_enable_sandbox", "Enable the V8 sandbox") orelse false,
        .v8_enable_direct_handle = b.option(bool, "v8_enable_direct_handle", "Use V8 direct handles (changes the C ABI; re-run `zig build gen`)") orelse false,
        .mac_sdk_path = b.option([]const u8, "mac_sdk_path", "macOS SDK directory to build V8 against (e.g. an older SDK when V8 does not build with the newest)"),
    };
    const cache_root = b.option([]const u8, "cache_root", "Directory holding the V8 and depot_tools checkouts") orelse b.root.joinString(b.allocator, ".lp-cache") catch @panic("OOM");

    const v8_dir = b.fmt("{s}/v8-{s}", .{ cache_root, version });
    const depot_dir = b.fmt("{s}/depot_tools-{s}", .{ cache_root, version });
    const args = gn_args.render(b, target);
    // Different GN args must not share a ninja output directory.
    const out_dir = b.fmt("out/{s}-{s}-{s}-{x}", .{
        gnOs(target),
        gnCpu(target),
        if (gn_args.is_debug) "debug" else "release",
        std.hash.Wyhash.hash(0, args),
    });

    // 1. Stage the shims. rsync only rewrites files whose content changed, so
    //    ninja's mtime tracking stays accurate.
    const staged = b.addWriteFiles();
    for (shims) |shim| _ = staged.addCopyFile(b.path(shim.src), shim.dest);
    const zstd = b.dependency("zstd", .{});
    _ = staged.addCopyFile(zstd.path("lib/zstd.h"), "zig/zstd/lib/zstd.h");
    _ = staged.addCopyFile(zstd.path("LICENSE"), "zig/zstd/LICENSE");

    const stage = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p \"$2\" && rsync -rc \"$1/\" \"$2/\"", "stage" });
    stage.addDirectoryArg(staged.getDirectory());
    stage.addArg(v8_dir);
    stage.has_side_effects = true;

    // 2. depot_tools, the V8 checkout and the bundled clang.
    const depot_tools = b.dependency("depot_tools", .{});
    const fetch = b.addSystemCommand(&.{"sh"});
    fetch.addFileArg(b.path("build-tools/fetch-v8.sh"));
    fetch.addArgs(&.{ cache_root, version });
    fetch.addDirectoryArg(depot_tools.path(""));
    fetch.has_side_effects = true;
    fetch.step.dependOn(&stage.step);

    // 3. Apply our versioned engine patch. Never silently skip an upgrade conflict.
    const patch = b.addSystemCommand(&.{"sh"});
    patch.addFileArg(b.path("build-tools/apply-v8-patches.sh"));
    patch.addArg(v8_dir);
    patch.addFileArg(b.path("build-tools/v8-intrinsics.patch"));
    patch.addFileArg(b.path("build-tools/v8-hardening.patch"));
    patch.has_side_effects = true;
    patch.step.dependOn(&fetch.step);

    // PartitionAlloc has its own checkout; defer optional Darwin frameworks.
    const pa_patch = b.addSystemCommand(&.{"sh"});
    pa_patch.addFileArg(b.path("build-tools/apply-v8-patches.sh"));
    pa_patch.addArg(b.fmt("{s}/third_party/partition_alloc", .{v8_dir}));
    pa_patch.addFileArg(b.path("build-tools/partition-alloc-lazy-frameworks.patch"));
    pa_patch.has_side_effects = true;
    pa_patch.step.dependOn(&patch.step);

    // ICU is a separate Git checkout, so apply its loader patch at its own root.
    const icu_patch = b.addSystemCommand(&.{"sh"});
    icu_patch.addFileArg(b.path("build-tools/apply-v8-patches.sh"));
    icu_patch.addArg(b.fmt("{s}/third_party/icu", .{v8_dir}));
    icu_patch.addFileArg(b.path("build-tools/icu-lazy-data.patch"));
    icu_patch.has_side_effects = true;
    icu_patch.step.dependOn(&pa_patch.step);

    // 4. Compress the complete ICU package before GN resolves generated sources.
    const compress = b.addSystemCommand(&.{ "uv", "run" });
    compress.addFileArg(b.path("build-tools/compress-icu.py"));
    const icu_data_dir = if (target.result.os.tag == .ios) "ios" else "common";
    compress.addArg(b.fmt("{s}/third_party/icu/{s}/icudtl.dat", .{ v8_dir, icu_data_dir }));
    compress.addArg(b.fmt("{s}/zig/binding/icu-data.gen.cc", .{v8_dir}));
    compress.has_side_effects = true;
    compress.step.dependOn(&icu_patch.step);

    // 5. Generate and build.
    const path_env = b.fmt("{s}:{s}", .{ depot_dir, b.graph.environ_map.get("PATH") orelse "" });

    const gn = b.addSystemCommand(&.{
        b.fmt("{s}/gn", .{depot_dir}),
        "--root=.",
        "--root-target=//zig",
        "--dotfile=zig/.gn",
        "gen",
        out_dir,
        // Lets tools/bindgen reuse the exact compiler flags of binding.cc.
        "--export-compile-commands=v8_zig",
        b.fmt("--args={s}", .{args}),
    });
    gn.setCwd(.{ .cwd_relative = v8_dir });
    gn.setEnvironmentVariable("PATH", path_env);
    gn.has_side_effects = true;
    gn.step.dependOn(&compress.step);

    const ninja = b.addSystemCommand(&.{ b.fmt("{s}/autoninja", .{depot_dir}), "-C", out_dir, "v8_zig" });
    ninja.setCwd(.{ .cwd_relative = v8_dir });
    ninja.setEnvironmentVariable("PATH", path_env);
    ninja.has_side_effects = true;
    ninja.step.dependOn(&gn.step);

    // Zig builds only zstd's decoder with .small; flatten it into the V8 archive.
    const decoder = zstd_build.add(b, target);
    b.step("build-zstd", "Build and install the size-optimized zstd decoder").dependOn(&b.addInstallArtifact(decoder, .{}).step);
    const bundle = b.addSystemCommand(&.{"sh"});
    bundle.addFileArg(b.path("build-tools/bundle-archives.sh"));
    bundle.addArg(b.graph.zig_exe);
    const lib = bundle.addOutputFileArg("libv8_zig.a");
    bundle.addFileArg(.{ .cwd_relative = b.fmt("{s}/{s}/obj/zig/libv8_zig.a", .{ v8_dir, out_dir }) });
    bundle.addArtifactArg(decoder);
    bundle.step.dependOn(&ninja.step);

    if (target.result.os.tag == .macos) {
        const native_test_module = b.createModule(.{
            .target = target,
            .optimize = .small,
            .link_libc = true,
            .link_libcpp = true,
        });
        native_test_module.addCSourceFile(.{ .file = b.path("tests/darwin-frameworks.cc"), .flags = &.{"-std=c++20"} });
        native_test_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/third_party/partition_alloc/src", .{v8_dir}) });
        native_test_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/{s}/gen", .{ v8_dir, out_dir }) });
        native_test_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/{s}/gen/third_party/partition_alloc/src", .{ v8_dir, out_dir }) });
        native_test_module.addSystemFrameworkPath(.{ .cwd_relative = b.fmt("{s}/System/Library/Frameworks", .{gn_args.mac_sdk_path orelse "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"}) });
        native_test_module.addObjectFile(lib);
        const native_test = b.addExecutable(.{ .name = "darwin-frameworks-test", .root_module = native_test_module, .use_llvm = true });
        const run_native_test = b.addRunArtifact(native_test);
        b.step("test-darwin-frameworks", "Test deferred macOS framework APIs and JIT policy").dependOn(&run_native_test.step);
        b.step("build-darwin-frameworks-test", "Install the native framework test for signing-policy checks").dependOn(&b.addInstallArtifact(native_test, .{}).step);
    }

    const step = b.step("build-v8", "Fetch and build V8");
    step.dependOn(&bundle.step);

    return .{
        .lib = lib,
        .build_dir = b.fmt("{s}/{s}", .{ v8_dir, out_dir }),
        .gn_step = &gn.step,
    };
}
