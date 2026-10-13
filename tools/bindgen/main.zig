//! Binding generator, run by `zig build gen`.
//!
//!   bindgen gen       <v8_build_dir> <layout.zon> <typemap.zon> <out binding.zig> <out layout.gen.h> <out externs.gen.zig>
//!   bindgen gen-check <same arguments>: fail if any output would change (nothing is written)
//!   bindgen check     <libv8_zig.a> <externs.gen.zig> <v8.zig> [<rusty_v8 binding.cc>]
//!
//! Everything is measured with V8's own clang using the exact flags GN uses
//! for binding.cc (see clang.zig), so the output reflects the real V8
//! configuration (pointer compression, sandbox, ...).

const std = @import("std");
const Io = std.Io;
const Clang = @import("clang.zig");
const externs = @import("externs.zig");
const check = @import("check.zig");

/// `gen-check`: compare instead of writing, so CI can prove the committed files are fresh.
var check_only = false;
var stale = false;

const LayoutManifest = struct {
    includes: []const []const u8,
    sizes: []const Sized,
    consts: []const Const,
    flags: []const Flag,

    const Sized = struct { name: []const u8, cpp: []const u8 };
    const Const = struct { name: []const u8, expr: []const u8 };
    /// A build option that changes the C++ ABI, detected from a macro V8's GN
    /// build defines. Becomes `binding.opts.<name>`.
    const Flag = struct { name: []const u8, define: []const u8 };
};

pub fn main(init: std.process.Init) !void {
    var arena_state: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len == 8 and (std.mem.eql(u8, args[1], "gen") or std.mem.eql(u8, args[1], "gen-check"))) {
        check_only = std.mem.eql(u8, args[1], "gen-check");
        try gen(arena, init.io, args[2], args[3], args[4], args[5], args[6], args[7]);
        if (stale) {
            std.debug.print("generated files are stale: run `zig build gen` and commit the result\n", .{});
            std.process.exit(1);
        }
        return;
    }
    if ((args.len == 5 or args.len == 6) and std.mem.eql(u8, args[1], "check")) {
        const ok = try check.run(arena, init.io, args[2], args[3], args[4], if (args.len == 6) args[5] else null);
        if (!ok) std.process.exit(1);
        return;
    }
    std.debug.print(
        "usage: bindgen gen|gen-check <v8_build_dir> <layout.zon> <typemap.zon> <out binding.zig> <out layout.gen.h> <out externs.gen.zig>\n" ++
            "       bindgen check <libv8_zig.a> <externs.gen.zig> <v8.zig> [<rusty_v8 binding.cc>]\n",
        .{},
    );
    std.process.exit(2);
}

fn gen(
    arena: std.mem.Allocator,
    io: Io,
    build_dir: []const u8,
    layout_path: []const u8,
    typemap_path: []const u8,
    out_zig: []const u8,
    out_h: []const u8,
    out_externs: []const u8,
) !void {
    const clang: Clang = try .load(arena, io, build_dir);
    const layout = try readZon(LayoutManifest, arena, io, layout_path);
    const typemap = try readZon(externs.TypeMap, arena, io, typemap_path);

    try genLayout(arena, io, clang, layout, out_zig, out_h);

    var out: Io.Writer.Allocating = .init(arena);
    const stats = try externs.generate(arena, clang, layout.includes, typemap, &out);
    try writeIfChanged(arena, io, out_externs, out.written());
    std.debug.print("externs: {d} generated, {d} not generated (listed at the end of {s})\n", .{ stats.emitted, stats.unmapped, std.fs.path.basename(out_externs) });
}

fn readZon(comptime T: type, arena: std.mem.Allocator, io: Io, path: []const u8) !T {
    const src = try Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20));
    var diag: std.zon.parse.Diagnostics = undefined;
    return std.zon.parse.fromSlice(T, .{
        .gpa = arena,
        .arena = arena,
        .source = try arena.dupeSentinel(u8, src, 0),
        .diagnostics = &diag,
    }) catch |err| {
        if (err == error.ParseZon) diag.log(path);
        return err;
    };
}

/// sizes/consts -> src/binding.zig plus static_asserts in binding/layout.gen.h.
fn genLayout(
    arena: std.mem.Allocator,
    io: Io,
    clang: Clang,
    m: LayoutManifest,
    out_zig: []const u8,
    out_h: []const u8,
) !void {
    var prelude: Io.Writer.Allocating = .init(arena);
    for (m.includes) |inc| try prelude.writer.print("#include \"{s}\"\n", .{inc});

    const probes = try arena.alloc(Clang.Probe, m.sizes.len + m.consts.len + m.flags.len);
    for (m.sizes, probes[0..m.sizes.len]) |s, *p| p.* = .{
        .name = try std.fmt.allocPrint(arena, "size_{s}", .{s.name}),
        .expr = try std.fmt.allocPrint(arena, "sizeof({s})", .{s.cpp}),
    };
    for (m.consts, probes[m.sizes.len..][0..m.consts.len]) |c, *p| p.* = .{
        .name = try std.fmt.allocPrint(arena, "const_{s}", .{c.name}),
        .expr = c.expr,
    };
    for (m.flags, probes[m.sizes.len + m.consts.len ..]) |f, *p| p.* = .{
        .name = try std.fmt.allocPrint(arena, "flag_{s}", .{f.name}),
        .ifdef = f.define,
    };
    const values = try clang.measure("layout_probe", prelude.written(), probes);

    var zig_out: Io.Writer.Allocating = .init(arena);
    var h_out: Io.Writer.Allocating = .init(arena);
    const zw = &zig_out.writer;
    const hw = &h_out.writer;

    try zw.writeAll("// Generated by tools/bindgen from build-tools/layout.zon (`zig build gen`) - DO NOT EDIT.\n\n");
    try hw.writeAll("// Generated by tools/bindgen from build-tools/layout.zon (`zig build gen`) - DO NOT EDIT.\n");
    try hw.writeAll("// If one of these fails, V8 or its build flags changed: run `zig build gen`.\n");
    try hw.writeAll("#pragma once\n\n#include <cstddef>\n#include <cstdint>\n\n");
    for (m.includes) |inc| try hw.print("#include \"{s}\"\n", .{inc});
    // `zig build gen` compiles with -DBINDGEN so it can run while these are stale.
    try hw.writeAll("\n#ifndef BINDGEN\n");

    try zw.writeAll("pub const sizes = struct {\n");
    for (m.sizes, values[0..m.sizes.len]) |s, value| {
        try zw.print("    pub const {s} = {d};\n", .{ s.name, value });
        try hw.print("static_assert(sizeof({s}) == {d}, \"{s} size changed\");\n", .{ s.cpp, value, s.name });
    }
    try zw.writeAll("};\n\npub const consts = struct {\n");
    for (m.consts, values[m.sizes.len..][0..m.consts.len]) |c, value| {
        try zw.print("    pub const {s} = {d};\n", .{ c.name, value });
        try hw.print("static_assert(({s}) == {d}, \"{s} changed\");\n", .{ c.expr, value, c.name });
    }
    try zw.writeAll("};\n\npub const opts = struct {\n");
    for (m.flags, values[m.sizes.len + m.consts.len ..]) |f, value| {
        try zw.print("    pub const {s} = {};\n", .{ f.name, value != 0 });
        // The C++ side is compiled with the same flags: fail loudly if they diverge.
        const present: []const u8 = if (value != 0) "ifndef" else "ifdef";
        try hw.print("#{s} {s}\n#error \"{s} changed: run `zig build gen`\"\n#endif\n", .{ present, f.define, f.name });
    }
    try hw.writeAll("#endif  // BINDGEN\n");
    try zw.writeAll("};\n");

    try writeIfChanged(arena, io, out_zig, zig_out.written());
    try writeIfChanged(arena, io, out_h, h_out.written());
}

/// Leaves the file untouched when the content is identical so builds that
/// depend on it are not needlessly invalidated.
fn writeIfChanged(arena: std.mem.Allocator, io: Io, path: []const u8, data: []const u8) !void {
    const cwd = Io.Dir.cwd();
    if (cwd.readFileAlloc(io, path, arena, .limited(1 << 26))) |existing| {
        if (std.mem.eql(u8, existing, data)) return;
    } else |_| {}
    if (check_only) {
        stale = true;
        std.debug.print("stale: {s}\n", .{path});
        return;
    }
    try cwd.writeFile(io, .{ .sub_path = path, .data = data });
    std.debug.print("updated {s}\n", .{path});
}
