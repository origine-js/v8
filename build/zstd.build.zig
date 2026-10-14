const std = @import("std");

/// Borrows b/target during configuration. Returns a build-owned, size-optimized
/// static decoder; its source paths and allocations live through build teardown.
/// Includes no compression, dictionary-training, legacy, or CLI implementation.
/// Configuration allocation failure panics; compiler failures retain build outputs.
pub fn add(b: *std.Build, target: std.Build.ResolvedTarget) *std.Build.Step.Compile {
    const source = b.dependency("zstd", .{});
    const module = b.createModule(.{
        .target = target,
        .optimize = .small,
        .link_libc = true,
        .pic = true,
        .strip = true,
    });
    module.addCSourceFiles(.{
        .root = source.path("lib"),
        .files = &.{
            "common/debug.c",
            "common/entropy_common.c",
            "common/error_private.c",
            "common/fse_decompress.c",
            "common/xxhash.c",
            "common/zstd_common.c",
            "decompress/huf_decompress.c",
            "decompress/zstd_ddict.c",
            "decompress/zstd_decompress.c",
            "decompress/zstd_decompress_block.c",
        },
        .flags = &.{ "-std=c99", "-DZSTD_DISABLE_ASM", "-DZSTD_LEGACY_SUPPORT=0", "-DZSTD_STRIP_ERROR_STRINGS" },
    });
    return b.addLibrary(.{
        .name = "zstd_decoder",
        .linkage = .static,
        .root_module = module,
        .use_llvm = true,
    });
}
