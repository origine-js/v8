//! The ICU data provider as its own link object (`libv8_icu.a`), not part of `libv8_zig.a`.
//! `-Dv8_icu=compressed` (default) embeds the package as one zstd frame that the provider
//! expands on first Intl use (about 3.8 MB, plus the size-optimized zstd decoder, and the
//! 10.8 MB heap copy once expanded). `-Dv8_icu=raw` embeds the package as it is (about 7 MB
//! more executable, no expansion, no heap copy: ICU reads the executable's pages directly).
//! Either way the program gets `v8_zig_icu_initialize` (binding/icu.h) from this archive.

const std = @import("std");
const zstd_build = @import("zstd.build.zig");

pub const Mode = enum { compressed, raw };

/// Everything the provider needs from the V8 checkout. Paths are borrowed through build teardown.
pub const Inputs = struct {
    /// `<v8>/third_party/icu`: headers come from `source/common`, the package from
    /// `<data_dir>/icudtl.dat`.
    icu_dir: []const u8,
    data_dir: []const u8,
    /// Completes once the checkout exists and the ICU patch series is applied.
    checkout: *std.Build.Step,
    /// The generated `icu-data.gen.cc` (compressed mode only; see compress-icu.py).
    compressed_source: ?std.Build.LazyPath,
};

/// Defines ICU's own headers need to produce the same (version-suffixed) symbol names as
/// the ICU that GN builds into V8; kept in step with //third_party/icu's public config.
const icu_flags = [_][]const u8{
    "-std=c++20",
    "-fno-exceptions",
    "-fno-rtti",
    "-DU_USING_ICU_NAMESPACE=0",
    "-DU_ENABLE_DYLOAD=0",
    "-DUSE_CHROMIUM_ICU=1",
    "-DU_ENABLE_TRACING=1",
    "-DU_ENABLE_RESOURCE_TRACING=0",
    "-DU_STATIC_IMPLEMENTATION",
    "-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE",
};

/// Returns the static library holding the selected provider. Borrows b and inputs through
/// build teardown; compiler failures retain build outputs.
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, mode: Mode, inputs: Inputs) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = .ReleaseSmall,
        .link_libc = true,
        .link_libcpp = true,
        .pic = true,
        .strip = true,
    });
    module.addIncludePath(b.path("binding"));
    module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/source/common", .{inputs.icu_dir}) });
    switch (mode) {
        .compressed => {
            zstd_build.addSources(b, module);
            module.addCSourceFiles(.{ .root = b.path("binding"), .files = &.{"icu-compressed.cc"}, .flags = &icu_flags });
            module.addCSourceFile(.{ .file = inputs.compressed_source.?, .flags = &icu_flags });
        },
        .raw => {
            module.addCSourceFiles(.{ .root = b.path("binding"), .files = &.{"icu-raw.cc"}, .flags = &icu_flags });
            module.addAssemblyFile(b.path("binding/icu-raw-data.S"));
            // Passed to the assembler's preprocessor as a string literal for `.incbin`.
            module.addCMacro("ICU_DATA_PATH", b.fmt("\"{s}/icudtl.dat\"", .{inputs.data_dir}));
        },
    }
    const lib = b.addLibrary(.{ .name = "v8_icu", .linkage = .static, .root_module = module, .use_llvm = true });
    lib.step.dependOn(inputs.checkout);
    return lib;
}
