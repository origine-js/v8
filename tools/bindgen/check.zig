//! `bindgen check`: keeps the views of the C ABI honest.
//!
//!   lib      the `v8__*` and `simdutf__*` symbols the built libv8_zig.a really exports (nm)
//!   gen      the externs (v8__* and simdutf__*) in src/generated/externs.gen.zig
//!   wrapped  the externs src/v8/*.zig actually calls (`e.v8__*`, `e.simdutf__*`)
//!   shims    the shims in binding/rusty.cc: exported for rusty_v8 only, so they
//!            are expected in `lib` without a Zig extern
//!   rusty    optional: the shims upstream rusty_v8 defines, as a porting checklist
//!
//! A mismatch between `lib` and `gen` is a hard failure (stale generated file or
//! a shim without a signature). The rest is a report: what is not wrapped yet
//! and what rusty_v8 has that this repo does not.

const std = @import("std");
const Io = std.Io;

const Set = std.array_hash_map.String(void);

/// Returns false when the library and the generated externs disagree.
pub fn run(
    arena: std.mem.Allocator,
    io: Io,
    lib_path: []const u8,
    externs_path: []const u8,
    wrapper_path: []const u8,
    shims_path: []const u8,
    rusty_path: ?[]const u8,
) !bool {
    const cwd = Io.Dir.cwd();

    const lib = try libSymbols(arena, io, lib_path);
    const shims = try definitions(arena, try cwd.readFileAlloc(io, shims_path, arena, .limited(1 << 26)));
    const externs_src = try cwd.readFileAlloc(io, externs_path, arena, .limited(1 << 26));
    const gen = try collect(arena, externs_src, "pub extern fn ");
    var wrapped: Set = .empty;
    {
        var dir = try cwd.openDir(io, wrapper_path, .{ .iterate = true });
        defer dir.close(io);
        var walker = try dir.walk(arena);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".zig")) continue;
            const src = try dir.readFileAlloc(io, entry.path, arena, .limited(1 << 26));
            for ((try collect(arena, src, "e.")).keys()) |n| try wrapped.put(arena, n, {});
        }
    }

    var ok = true;

    // 1. library <-> generated externs (hard failure).
    const only_lib = try difference(arena, try difference2(arena, lib, shims), gen);
    const only_gen = try difference(arena, gen, lib);
    if (only_lib.len != 0 or only_gen.len != 0) {
        ok = false;
        std.debug.print("FAIL: libv8_zig.a and src/generated/externs.gen.zig disagree; run `zig build gen`.\n", .{});
        for (only_lib) |n| std.debug.print("  exported but not declared: {s}\n", .{n});
        for (only_gen) |n| std.debug.print("  declared but not exported: {s}\n", .{n});
    } else {
        std.debug.print("ok: {d} shims exported by the library, all declared in externs.gen.zig\n", .{lib.count()});
    }

    // 2. generated externs the wrappers do not call yet.
    var unwrapped: std.ArrayList([]const u8) = .empty;
    // `__SIZEOF` shims only feed build-time layout checks; there is nothing to wrap.
    var layout_shims: usize = 0;
    for (gen.keys()) |n| {
        if (std.mem.endsWith(u8, n, "__SIZEOF")) layout_shims += 1;
        if (!wrapped.contains(n) and !std.mem.endsWith(u8, n, "__SIZEOF")) try unwrapped.append(arena, n);
    }
    std.debug.print("\nwrapped by v8.zig: {d} of {d} runtime shims; not wrapped yet: {d} ({d} layout shims excluded)\n", .{ gen.count() - layout_shims - unwrapped.items.len, gen.count() - layout_shims, unwrapped.items.len, layout_shims });
    try printByClass(arena, unwrapped.items);

    // 3. what rusty_v8 has that we do not.
    if (rusty_path) |path| {
        const src = try cwd.readFileAlloc(io, path, arena, .limited(1 << 26));
        const rusty = try definitions(arena, src);
        const missing = try difference(arena, rusty, lib);
        std.debug.print(
            "\nrusty_v8 defines {d} shims; {d} are missing here (its V8 is newer, so some are expected):\n",
            .{ rusty.count(), missing.len },
        );
        try printByClass(arena, missing);
    } else {
        std.debug.print("\n(rusty_v8 comparison skipped: dependency not fetched)\n", .{});
    }

    return ok;
}

/// Borrows io/lib_path through subprocess completion; returns an arena-owned set
/// valid until arena teardown. Reads native symbols only on macOS, ignoring
/// embedded Rust LLVM bitcode. Errors retain only arena allocations; no library
/// data is modified. macOS prefixes C symbols with `_`.
fn libSymbols(arena: std.mem.Allocator, io: Io, lib_path: []const u8) !Set {
    const result = try std.process.run(arena, io, .{
        .argv = if (@import("builtin").os.tag.isDarwin())
            &.{ "nm", "--no-llvm-bc", "-g", lib_path }
        else
            &.{ "nm", "-g", lib_path },
        .stdout_limit = .limited(1 << 28),
    });
    if (!result.term.success()) {
        std.debug.print("nm failed:\n{s}\n", .{result.stderr});
        return error.NmFailed;
    }
    var set: Set = .empty;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        var last: []const u8 = "";
        var prev: []const u8 = "";
        while (tokens.next()) |t| {
            prev = last;
            last = t;
        }
        // `<addr> T <symbol>`
        if (!std.mem.eql(u8, prev, "T")) continue;
        const name = if (last.len != 0 and last[0] == '_') last[1..] else last;
        if (isShimName(name)) try set.put(arena, name, {});
    }
    return set;
}

/// Identifiers `v8__<name>` that directly follow `prefix`.
fn collect(arena: std.mem.Allocator, src: []const u8, prefix: []const u8) !Set {
    var set: Set = .empty;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, src, pos, prefix)) |at| {
        pos = at + prefix.len;
        const rest = src[pos..];
        if (!isShimName(rest)) continue;
        var end: usize = 0;
        while (end < rest.len and isIdent(rest[end])) end += 1;
        try set.put(arena, rest[0..end], {});
    }
    return set;
}

/// Function definitions in a binding.cc: `v8__name(` on a line that starts in
/// column 0 (return type and name on one line, as clang-format emits them).
fn definitions(arena: std.mem.Allocator, src: []const u8) !Set {
    var set: Set = .empty;
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or !std.ascii.isAlphabetic(line[0])) continue;
        const at = std.mem.indexOf(u8, line, "v8__") orelse std.mem.indexOf(u8, line, "simdutf__") orelse continue;
        var end = at;
        while (end < line.len and isIdent(line[end])) end += 1;
        if (end >= line.len or line[end] != '(') continue;
        // Skip `using v8__X = ...;` / `static ... v8__X = ...;` style lines.
        if (std.mem.indexOfScalar(u8, line[0..at], '=') != null) continue;
        try set.put(arena, line[at..end], {});
    }
    return set;
}

/// Whether `s` starts with a covered shim prefix (`v8__` or `simdutf__`).
/// Pure string test; retains nothing.
fn isShimName(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "v8__") or std.mem.startsWith(u8, s, "simdutf__");
}

fn isIdent(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Returns `a` without the members of `b` (arena-owned).
fn difference2(arena: std.mem.Allocator, a: Set, b: Set) !Set {
    var out: Set = .empty;
    for (a.keys()) |k| if (!b.contains(k)) try out.put(arena, k, {});
    return out;
}

fn difference(arena: std.mem.Allocator, a: Set, b: Set) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (a.keys()) |k| if (!b.contains(k)) try out.append(arena, k);
    std.mem.sort([]const u8, out.items, {}, lessThan);
    return out.items;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// `v8__Object__Get` -> class `Object` (all `simdutf__*` go under class `simdutf`); one line per class with its methods.
fn printByClass(arena: std.mem.Allocator, names: []const []const u8) !void {
    var classes: std.array_hash_map.String(std.ArrayList([]const u8)) = .empty;
    for (names) |n| {
        // The simdutf shims are free functions: one `simdutf` class.
        const is_simdutf = std.mem.startsWith(u8, n, "simdutf__");
        const body = if (is_simdutf) n["simdutf__".len..] else n["v8__".len..];
        const split = if (is_simdutf) 0 else std.mem.indexOf(u8, body, "__") orelse body.len;
        const gop = try classes.getOrPut(arena, if (is_simdutf) "simdutf" else body[0..split]);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(arena, if (is_simdutf) body else if (split < body.len) body[split + 2 ..] else "");
    }
    const Ctx = struct {
        keys: []const []const u8,
        pub fn lessThan(self: @This(), a: usize, b: usize) bool {
            return std.mem.lessThan(u8, self.keys[a], self.keys[b]);
        }
    };
    classes.sort(Ctx{ .keys = classes.keys() });
    for (classes.keys(), classes.values()) |class, methods| {
        std.debug.print("  {s} ({d}):", .{ class, methods.items.len });
        for (methods.items) |m| std.debug.print(" {s}", .{m});
        std.debug.print("\n", .{});
    }
}
