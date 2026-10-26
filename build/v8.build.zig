//! Builds V8 plus our C++ shim (`binding/`) into a single static library.
//!
//! Pipeline: stage shims into the V8 tree -> fetch (depot_tools, gclient, clang)
//! -> `gn gen` -> `autoninja`. Every stage is idempotent and defers to
//! rsync/markers/ninja for incrementality, but starting ninja alone costs hundreds of
//! milliseconds. The pipeline therefore runs only for the explicit `build-v8` step (or
//! when no archive has been built yet); it publishes the archive at a stable path that
//! ordinary builds link without re-checking V8.

const std = @import("std");
const zstd_build = @import("zstd.build.zig");

const LazyPath = std.Build.LazyPath;

pub const version = "15.8.30";

pub const V8 = struct {
    /// `libv8_zig.a`, a complete static library containing V8 and the shim.
    lib: LazyPath,
    /// Like `lib` but without the bundled temporal_capi rlibs, for final links that get
    /// `temporal_capi` elsewhere (rusty_v8 pulls it from crates.io). Equals `lib` when
    /// Temporal is disabled or the library is prebuilt.
    lib_no_temporal: LazyPath,
    /// GN output directory (holds compile_commands.json). Null for prebuilt libraries.
    build_dir: ?[]const u8 = null,
    /// Finishes once GN has generated `build_dir`. Null for prebuilt libraries.
    gn_step: ?*std.Build.Step = null,
    /// Build-owned matching LLVM tool directory, valid through build teardown.
    clang_bin: ?[]const u8 = null,
};

/// Files copied into the V8 checkout. `src` is relative to this repository,
/// `dest` to the V8 source root.
const shims = [_]struct { src: []const u8, dest: []const u8 }{
    .{ .src = "binding/binding.cc", .dest = "zig/binding/binding.cc" },
    .{ .src = "binding/rusty.cc", .dest = "zig/binding/rusty.cc" },
    .{ .src = "binding/binding.hpp", .dest = "zig/binding/binding.hpp" },
    .{ .src = "binding/icu-compressed.cc", .dest = "zig/binding/icu-compressed.cc" },
    .{ .src = "binding/darwin-frameworks.cc", .dest = "zig/binding/darwin-frameworks.cc" },
    .{ .src = "binding/icu-compressed.h", .dest = "zig/binding/icu-compressed.h" },
    .{ .src = "binding/support.h", .dest = "zig/binding/support.h" },
    .{ .src = "binding/layout.gen.h", .dest = "zig/binding/layout.gen.h" },
    .{ .src = "build-tools/gn/BUILD.gn", .dest = "zig/BUILD.gn" },
    .{ .src = "build-tools/gn/.gn", .dest = "zig/.gn" },
};

const GnArgs = struct {
    is_debug: bool,
    symbol_level: u8,
    is_asan: bool,
    is_tsan: bool,
    v8_sandbox: bool,
    /// Pass V8 handles as direct object addresses. This changes the C ABI, so
    /// `zig build gen` must be re-run after toggling it (src/generated/binding.zig and
    /// binding/layout.gen.h record the configuration).
    v8_enable_direct_handle: bool,
    /// macOS SDK to compile against; GN picks the newest installed one when null.
    mac_sdk_path: ?[]const u8,
    /// Drop C++ unwind tables. V8 is built without exceptions, so they only
    /// serve backtraces. Spelled out only when enabled, like the other opt-ins.
    exclude_unwind_tables: bool,
    /// Compile with size-favouring inlining and optimisation levels.
    optimize_for_size: bool,
    /// Build the per-call runtime statistics counters (slower, larger).
    runtime_call_stats: bool,
    /// Compile release V8 as ThinLTO bitcode. Zig's Mach-O linker cannot consume bitcode, so
    /// Darwin consumers either link with V8's ld64.lld (root build) or convert the archive
    /// to native objects (build.zig `native-archive.py` step).
    thin_lto: bool,
    /// Build the Temporal API (pulls in the Rust temporal_capi and time zone data).
    temporal: bool,
    /// Build V8's WebAssembly engine (Liftoff/TurboFan wasm, trap handler).
    webassembly: bool,
    /// Use Google's exact-version builtin profile; V8 checks hashes and discards mismatches.
    builtin_pgo: bool,

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
        // Preserve the full ICU backend used by our compressed-data provider and
        // locale API. V8 15.8 otherwise defaults to the distinct ICU4X backend.
        lines.append(a, "v8_enable_ecma402_icu4x=false") catch @panic("OOM");
        lines.append(a, b.fmt("is_debug={}", .{self.is_debug})) catch @panic("OOM");
        if (!self.is_debug) {
            lines.append(a, "is_clang=true") catch @panic("OOM");
            lines.append(a, b.fmt("use_thin_lto={}", .{self.thin_lto})) catch @panic("OOM");
        }
        lines.append(a, b.fmt("symbol_level={d}", .{self.symbol_level})) catch @panic("OOM");
        lines.append(a, b.fmt("is_asan={}", .{self.is_asan})) catch @panic("OOM");
        lines.append(a, b.fmt("is_tsan={}", .{self.is_tsan})) catch @panic("OOM");
        lines.append(a, b.fmt("v8_enable_sandbox={}", .{self.v8_sandbox})) catch @panic("OOM");
        lines.append(a, b.fmt("v8_enable_webassembly={}", .{self.webassembly})) catch @panic("OOM");
        // Only spelled out when enabled so the default configuration keeps its build directory.
        if (self.v8_enable_direct_handle) lines.append(a, "v8_enable_direct_handle=true") catch @panic("OOM");
        if (self.exclude_unwind_tables) lines.append(a, "exclude_unwind_tables=true") catch @panic("OOM");
        if (self.optimize_for_size) lines.append(a, "optimize_for_size=true") catch @panic("OOM");
        if (!self.runtime_call_stats) lines.append(a, "v8_enable_runtime_call_stats=false") catch @panic("OOM");
        if (!self.temporal) lines.append(a, "v8_enable_temporal_support=false") catch @panic("OOM");
        if (self.builtin_pgo) {
            lines.appendSlice(a, &.{
                "v8_enable_builtins_optimization=true",
                "v8_enable_builtins_profiling=false",
                "dcheck_always_on=false",
            }) catch @panic("OOM");
            if (customBuiltinPgo(target)) {
                lines.appendSlice(a, &.{
                    "v8_zig_custom_builtin_pgo=true",
                    "v8_builtins_profiling_log_file=\"//tools/builtins-pgo/profiles/origine-mac-arm64.profile\"",
                }) catch @panic("OOM");
            } else {
                lines.append(a, b.fmt("v8_builtins_profiling_log_file=\"//tools/builtins-pgo/profiles/{s}.profile\"", .{googleProfile(target)})) catch @panic("OOM");
            }
        }

        if (self.mac_sdk_path) |path| {
            lines.append(a, b.fmt("mac_sdk_path=\"{s}\"", .{path})) catch @panic("OOM");
        }

        switch (target.result.os.tag) {
            .ios => lines.appendSlice(a, &.{
                "v8_enable_pointer_compression=false",
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

/// Copies the target descriptor; returns a value and retains no resources.
fn customBuiltinPgo(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .macos and target.result.cpu.arch == .aarch64;
}

/// Accepts a target descriptor and returns a static profile name; retains no resources.
fn googleProfile(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.cpu.arch) {
        .aarch64, .x86_64 => "x64",
        .arm, .x86 => "x86",
        else => @panic("Google builtin PGO supports arm64/x64/arm/x86; pass -Dbuiltin_pgo=false"),
    };
}

const Bundle = struct { lib: LazyPath, run: *std.Build.Step.Run };

/// Flattens V8's archive, the zstd decoder and (optionally) the temporal_capi rlibs into one
/// `libv8_zig.a`. Borrows b, the decoder and the dependency step for graph construction;
/// the output is build-cache owned. `with_rust` adds the Rust rlibs GN's alink drops.
fn bundleArchive(
    b: *std.Build,
    v8_dir: []const u8,
    out_dir: []const u8,
    decoder: *std.Build.Step.Compile,
    bitcode_darwin: bool,
    with_rust: bool,
    after: *std.Build.Step,
) Bundle {
    const bundle = b.addSystemCommand(&.{"sh"});
    bundle.addFileArg(b.path("build-tools/scripts/bundle-archives.sh"));
    if (bitcode_darwin) {
        bundle.addArg(b.fmt("{s}/third_party/llvm-build/Release+Asserts/bin/llvm-ar", .{v8_dir}));
        bundle.addArg("-");
    } else {
        bundle.addArgs(&.{ b.graph.zig_exe, "ar" });
    }
    const lib = bundle.addOutputFileArg("libv8_zig.a");
    if (with_rust) {
        // temporal_capi is Rust; GN's alink drops rlibs from static libraries (rusty_v8 gets
        // them through Cargo), so the bundler adds them. Host-side proc-macro rlibs are skipped.
        bundle.addArgs(&.{ "--rust", b.fmt("{s}/third_party/ninja/ninja", .{v8_dir}), b.fmt("{s}/{s}", .{ v8_dir, out_dir }), "v8_zig" });
    }
    bundle.addFileArg(.{ .cwd_relative = b.fmt("{s}/{s}/obj/zig/libv8_zig.a", .{ v8_dir, out_dir }) });
    bundle.addArtifactArg(decoder);
    bundle.step.dependOn(after);
    return .{ .lib = lib, .run = bundle };
}

/// Copies `src` to a build-cache output and to the stable `dest` path (skipping the
/// write when identical, so mtimes stay put). Borrows b, src and dest through graph
/// construction; the stable file is owned by the cache directory, the output by the build cache.
fn publish(b: *std.Build, src: LazyPath, dest: []const u8) Bundle {
    const run = b.addSystemCommand(&.{ "sh", "-c", "cmp -s \"$1\" \"$2\" || { mkdir -p \"$(dirname \"$2\")\" && cp -f \"$1\" \"$2\"; } && cp -f \"$1\" \"$3\"", "publish" });
    run.addFileArg(src);
    run.addArg(dest);
    return .{ .lib = run.addOutputFileArg(std.fs.path.basename(dest)), .run = run };
}

/// Reports whether the absolute `path` exists; borrows b and path, retains nothing.
fn exists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(b.graph.io, path, .{}) catch return false;
    return true;
}

/// Adds a step that syncs `checkout` with the series in `build-tools/patches/<series>`.
/// Borrows `b` and `checkout` for graph construction; the step re-runs every build
/// (the applier is incremental and idempotent). Returns a builder-owned run step.
fn applyPatches(b: *std.Build, checkout: []const u8, series: []const u8) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{"sh"});
    run.addFileArg(b.path("build-tools/scripts/apply-patches.sh"));
    run.addArg(checkout);
    run.addDirectoryArg(b.path(b.fmt("build-tools/patches/{s}", .{series})));
    run.has_side_effects = true;
    return run;
}

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
        return .{ .lib = .{ .cwd_relative = path }, .lib_no_temporal = .{ .cwd_relative = path } };
    }

    const gn_args: GnArgs = .{
        .is_debug = optimize == .debug,
        .symbol_level = b.option(u8, "symbol_level", "GN symbol_level") orelse if (optimize == .debug) 1 else 0,
        .is_asan = b.option(bool, "is_asan", "Build V8 with AddressSanitizer") orelse false,
        .is_tsan = b.option(bool, "is_tsan", "Build V8 with ThreadSanitizer") orelse false,
        .v8_sandbox = b.option(bool, "v8_sandbox", "Enable the V8 sandbox (default: on; requires pointer compression)") orelse true,
        .v8_enable_direct_handle = b.option(bool, "v8_enable_direct_handle", "Use V8 direct handles (changes the C ABI; re-run `zig build gen`)") orelse false,
        .exclude_unwind_tables = b.option(bool, "exclude_unwind_tables", "Omit C++ unwind tables from V8 (default: on for release V8)") orelse (optimize != .debug),
        .optimize_for_size = b.option(bool, "optimize_for_size", "Favour code size over speed when compiling V8") orelse false,
        .runtime_call_stats = b.option(bool, "runtime_call_stats", "Build V8 runtime call statistics") orelse true,
        .thin_lto = b.option(bool, "thin_lto", "Build release V8 as ThinLTO bitcode (default: on; Darwin Zig links convert it to native objects)") orelse true,
        .temporal = b.option(bool, "temporal", "Build the Temporal API") orelse true,
        .webassembly = b.option(bool, "webassembly", "Build V8's WebAssembly engine") orelse true,
        .builtin_pgo = b.option(bool, "builtin_pgo", "Use Google's exact-version builtin PGO baseline (default: on for release desktop V8)") orelse (optimize != .debug and target.result.os.tag != .ios),
        .mac_sdk_path = b.option([]const u8, "mac_sdk_path", "macOS SDK directory to build V8 against; V8 15.8 GN rejects paths outside the build directory, so leave unset and select the SDK with xcode-select/DEVELOPER_DIR"),
    };
    if (gn_args.builtin_pgo and (gn_args.is_debug or !gn_args.webassembly or
        !gn_args.v8_sandbox or target.result.os.tag == .ios))
        @panic("Google builtin PGO requires release V8, WebAssembly, pointer compression and sandbox; pass -Dbuiltin_pgo=false for this configuration");
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
    _ = staged.addCopyFile(zstd.path("lib/zstd_errors.h"), "zig/zstd/lib/zstd_errors.h");
    _ = staged.addCopyFile(zstd.path("LICENSE"), "zig/zstd/LICENSE");

    const stage = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p \"$2\" && rsync -rc \"$1/\" \"$2/\"", "stage" });
    stage.addDirectoryArg(staged.getDirectory());
    stage.addArg(v8_dir);
    stage.has_side_effects = true;

    // 2. depot_tools, the V8 checkout and the bundled clang.
    const depot_tools = b.dependency("depot_tools", .{});
    const fetch = b.addSystemCommand(&.{"sh"});
    fetch.addFileArg(b.path("build-tools/scripts/fetch-v8.sh"));
    fetch.addArgs(&.{ cache_root, version });
    fetch.addDirectoryArg(depot_tools.path(""));
    fetch.has_side_effects = true;
    fetch.step.dependOn(&stage.step);

    // 3. Apply our versioned patch series (build-tools/patches/*). Each checkout is its own
    // git root; never silently skip an upgrade conflict.
    const patch = applyPatches(b, v8_dir, "v8");
    patch.step.dependOn(&fetch.step);

    // PartitionAlloc has its own checkout; defer optional Darwin frameworks.
    const pa_patch = applyPatches(b, b.fmt("{s}/third_party/partition_alloc", .{v8_dir}), "partition_alloc");
    pa_patch.step.dependOn(&patch.step);

    // ICU: loader hook for the compressed data provider.
    const icu_patch = applyPatches(b, b.fmt("{s}/third_party/icu", .{v8_dir}), "icu");
    icu_patch.step.dependOn(&pa_patch.step);

    // 4. Compress the complete ICU package before GN resolves generated sources.
    const compress = b.addSystemCommand(&.{ "uv", "run" });
    compress.addFileArg(b.path("build-tools/scripts/compress-icu.py"));
    const icu_data_dir = if (target.result.os.tag == .ios) "ios" else "common";
    compress.addArg(b.fmt("{s}/third_party/icu/{s}/icudtl.dat", .{ v8_dir, icu_data_dir }));
    const compressed_source = compress.addOutputFileArg2("icu-data.gen.cc", .{});
    compress.step.dependOn(&icu_patch.step);
    const published_icu = publish(b, compressed_source, b.fmt("{s}/zig/binding/icu-data.gen.cc", .{v8_dir}));

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
    gn.step.dependOn(&published_icu.run.step);
    if (gn_args.builtin_pgo) {
        const profiles = b.addSystemCommand(&.{ "uv", "run" });
        profiles.addFileArg(b.path("build-tools/scripts/download-pgo.py"));
        profiles.addArgs(&.{ v8_dir, googleProfile(target) });
        profiles.has_side_effects = true;
        profiles.step.dependOn(&fetch.step);
        if (customBuiltinPgo(target)) {
            const custom = b.addSystemCommand(&.{ "uv", "run" });
            custom.addFileArg(b.path("build-tools/scripts/prepare-custom-pgo.py"));
            custom.addArg(v8_dir);
            custom.addDirectoryArg(b.path(b.fmt("build-tools/pgo/profiles/{s}/mac-arm64", .{version})));
            custom.addArgs(&.{ "--gn-args", args });
            custom.has_side_effects = true;
            custom.step.dependOn(&profiles.step);
            custom.step.dependOn(&published_icu.run.step);
            gn.step.dependOn(&custom.step);
        } else {
            gn.step.dependOn(&profiles.step);
        }
    }

    const ninja = b.addSystemCommand(&.{ b.fmt("{s}/autoninja", .{depot_dir}), "-C", out_dir, "v8_zig" });
    ninja.setCwd(.{ .cwd_relative = v8_dir });
    ninja.setEnvironmentVariable("PATH", path_env);
    ninja.has_side_effects = true;
    ninja.step.dependOn(&gn.step);

    // Zig builds only zstd's decoder with .small; flatten it into the V8 archive.
    const decoder = zstd_build.add(b, target);
    b.step("build-zstd", "Build and install the size-optimized zstd decoder").dependOn(&b.addInstallArtifact(decoder, .{}).step);
    // `zig ar` writes no symbol index for bitcode members, so ThinLTO Darwin archives
    // are flattened with the llvm-ar that shipped with (and matches) V8's clang.
    const bitcode_darwin = !gn_args.is_debug and gn_args.thin_lto and target.result.os.tag.isDarwin();
    const bundle = bundleArchive(b, v8_dir, out_dir, decoder, bitcode_darwin, gn_args.temporal, &ninja.step);
    const stable_dir = b.fmt("{s}/{s}/zig-bundle", .{ v8_dir, out_dir });
    const stable_lib = b.fmt("{s}/libv8_zig.a", .{stable_dir});
    const stable_no_temporal = if (gn_args.temporal) b.fmt("{s}/libv8_zig_no_temporal.a", .{stable_dir}) else stable_lib;
    const published = publish(b, bundle.lib, stable_lib);
    const published_no_temporal = if (gn_args.temporal)
        publish(b, bundleArchive(b, v8_dir, out_dir, decoder, bitcode_darwin, false, &ninja.step).lib, stable_no_temporal)
    else
        published;
    // Without a built archive, linking pulls in the whole pipeline once. Afterwards the
    // archives are plain files and V8 is rebuilt only by `build-v8`.
    const have_archive = exists(b, stable_lib);
    const lib: LazyPath = if (have_archive) .{ .cwd_relative = stable_lib } else published.lib;
    const lib_no_temporal: LazyPath = if (exists(b, stable_no_temporal)) .{ .cwd_relative = stable_no_temporal } else published_no_temporal.lib;

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
        // Zig's Mach-O linker cannot consume the release archive's LLVM bitcode.
        // Use the same native-object conversion as the exported Zig module.
        const native_archive = b.addSystemCommand(&.{ "uv", "run", "--script" });
        native_archive.addFileArg(b.path("build-tools/scripts/native-archive.py"));
        native_archive.addFileArg(lib);
        const native_lib = native_archive.addOutputFileArg("libv8_zig.a");
        native_archive.addArg(b.fmt("{s}/third_party/llvm-build/Release+Asserts/bin", .{v8_dir}));
        native_archive.addArgs(&.{ "--target", b.fmt("{s}-apple-macos{f}", .{ @tagName(target.result.cpu.arch), target.result.os.version_range.semver.min }) });
        native_test_module.addObjectFile(native_lib);
        native_test_module.linkLibrary(b.dependency("mimalloc", .{ .target = target, .optimize = .safe }).artifact("mimalloc"));
        const native_test = b.addExecutable(.{ .name = "darwin-frameworks-test", .root_module = native_test_module, .use_llvm = true });
        const run_native_test = b.addRunArtifact(native_test);
        b.step("test-darwin-frameworks", "Test deferred macOS framework APIs and JIT policy").dependOn(&run_native_test.step);
        b.step("build-darwin-frameworks-test", "Install the native framework test for signing-policy checks").dependOn(&b.addInstallArtifact(native_test, .{}).step);
    }

    b.step("patch-v8", "Fetch V8 and apply the patch series without building").dependOn(&icu_patch.step);
    const step = b.step("build-v8", "Fetch, patch and rebuild V8 (ordinary builds reuse the last archive)");
    step.dependOn(&published.run.step);
    step.dependOn(&published_no_temporal.run.step);

    return .{
        .lib = lib,
        .lib_no_temporal = lib_no_temporal,
        .build_dir = b.fmt("{s}/{s}", .{ v8_dir, out_dir }),
        .gn_step = &gn.step,
        .clang_bin = b.fmt("{s}/third_party/llvm-build/Release+Asserts/bin", .{v8_dir}),
    };
}
