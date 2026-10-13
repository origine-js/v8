//! Runs V8's bundled clang with the exact flags GN uses for binding.cc
//! (taken from compile_commands.json) so every measurement and AST dump
//! reflects the real V8 configuration.

const std = @import("std");
const Io = std.Io;

const Clang = @This();

arena: std.mem.Allocator,
io: Io,
build_dir: []const u8,
/// Absolute path to clang++ followed by the flags, without source/output.
flags: []const []const u8,
/// binding.cc as GN names it (relative to `build_dir`).
source: []const u8,

pub const Probe = struct {
    /// Becomes the C symbol `probe_<name>`; its value is read back.
    name: []const u8,
    /// Integral constant expression. Ignored when `ifdef` is set.
    expr: []const u8 = "",
    /// When set, the probe is 1 if this preprocessor macro is defined, else 0.
    ifdef: ?[]const u8 = null,
};

const CompileEntry = struct {
    directory: []const u8,
    command: []const u8,
    file: []const u8,
};

pub fn load(arena: std.mem.Allocator, io: Io, build_dir: []const u8) !Clang {
    const db_path = try std.fmt.allocPrint(arena, "{s}/compile_commands.json", .{build_dir});
    const db_src = Io.Dir.cwd().readFileAlloc(io, db_path, arena, .limited(1 << 28)) catch |err| {
        std.debug.print("cannot read {s} ({t}); build V8 once so GN exports it\n", .{ db_path, err });
        return err;
    };
    const entries = try std.json.parseFromSliceLeaky([]const CompileEntry, arena, db_src, .{ .ignore_unknown_fields = true });
    const entry = for (entries) |e| {
        if (std.mem.endsWith(u8, e.file, "zig/binding/binding.cc")) break e;
    } else return error.BindingCompileCommandNotFound;

    var flags: std.ArrayList([]const u8) = .empty;
    const original = try shellSplit(arena, entry.command);
    var i: usize = 0;
    while (i < original.len) : (i += 1) {
        const a = original[i];
        if (std.mem.eql(u8, a, "-MD") or std.mem.eql(u8, a, "-c")) continue;
        if (std.mem.eql(u8, a, "-MF") or std.mem.eql(u8, a, "-o")) {
            i += 1;
            continue;
        }
        if (std.mem.endsWith(u8, a, ".cc")) continue;
        try flags.append(arena, a);
    }
    // The compiler is given relative to the GN build directory.
    flags.items[0] = try std.fs.path.resolve(arena, &.{ entry.directory, flags.items[0] });
    try flags.append(arena, "-Wno-error");
    // layout.gen.h disables its checks under this define, so regenerating can
    // never be blocked by the (possibly stale) file being regenerated.
    try flags.append(arena, "-DBINDGEN=1");

    return .{
        .arena = arena,
        .io = io,
        .build_dir = entry.directory,
        .flags = flags.items,
        .source = entry.file,
    };
}

/// Compiles a probe translation unit to assembly (never linked or run) and
/// reads back the value of each probe.
pub fn measure(
    self: Clang,
    unit: []const u8,
    prelude: []const u8,
    probes: []const Probe,
) ![]u64 {
    const cwd = Io.Dir.cwd();
    const src_path = try std.fmt.allocPrint(self.arena, "{s}/{s}.cc", .{ self.build_dir, unit });
    const asm_path = try std.fmt.allocPrint(self.arena, "{s}/{s}.s", .{ self.build_dir, unit });

    var src: Io.Writer.Allocating = .init(self.arena);
    const w = &src.writer;
    try w.writeAll("#include <cstdint>\n#include <type_traits>\n");
    try w.writeAll(prelude);
    try w.writeAll("\n#define PROBE(sym, expr) extern \"C\" const uint64_t sym = (uint64_t)(expr)\n");
    for (probes) |p| {
        if (p.ifdef) |macro| {
            try w.print("#ifdef {s}\nPROBE(probe_{s}, 1);\n#else\nPROBE(probe_{s}, 0);\n#endif\n", .{ macro, p.name, p.name });
        } else {
            try w.print("PROBE(probe_{s}, {s});\n", .{ p.name, p.expr });
        }
    }
    try cwd.writeFile(self.io, .{ .sub_path = src_path, .data = src.written() });

    try self.run(&.{ "-S", "-o", asm_path, src_path }, null);
    const asm_src = try cwd.readFileAlloc(self.io, asm_path, self.arena, .limited(1 << 26));

    const values = try self.arena.alloc(u64, probes.len);
    for (probes, values) |p, *v| v.* = try probeValue(self.arena, asm_src, p.name);
    return values;
}

/// Dumps the AST of binding.cc for declarations whose name contains `filter`.
pub fn astDump(self: Clang, filter: []const u8) ![]u8 {
    var out: []u8 = undefined;
    try self.run(&.{
        "-fsyntax-only",
        "-Xclang",
        "-ast-dump=json",
        "-Xclang",
        try std.fmt.allocPrint(self.arena, "-ast-dump-filter={s}", .{filter}),
        self.source,
    }, &out);
    return out;
}

fn run(self: Clang, extra: []const []const u8, stdout: ?*[]u8) !void {
    const argv = try std.mem.concat(self.arena, []const u8, &.{ self.flags, extra });
    const result = try std.process.run(self.arena, self.io, .{
        .argv = argv,
        .cwd = .{ .path = self.build_dir },
        .stdout_limit = .limited(1 << 30),
    });
    if (!result.term.success()) {
        std.debug.print("clang failed:\n{s}\n", .{result.stderr});
        return error.ClangFailed;
    }
    if (stdout) |p| p.* = result.stdout;
}

/// Splits a command line the way GN writes it: spaces separate arguments,
/// double quotes group, backslash escapes the next character.
fn shellSplit(arena: std.mem.Allocator, s: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var cur: std.ArrayList(u8) = .empty;
    var in_quote = false;
    var have = false;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '\\' and i + 1 < s.len) {
            i += 1;
            try cur.append(arena, s[i]);
            have = true;
        } else if (c == '"') {
            in_quote = !in_quote;
            have = true;
        } else if (c == ' ' and !in_quote) {
            if (have) try out.append(arena, try cur.toOwnedSlice(arena));
            have = false;
        } else {
            try cur.append(arena, c);
            have = true;
        }
    }
    if (have) try out.append(arena, try cur.toOwnedSlice(arena));
    return out.items;
}

/// Reads `probe_<name>` out of the assembly: the label, then the first 8-byte
/// data directive after it.
fn probeValue(arena: std.mem.Allocator, asm_src: []const u8, name: []const u8) !u64 {
    const symbol = try std.fmt.allocPrint(arena, "probe_{s}", .{name});
    var lines = std.mem.splitScalar(u8, asm_src, '\n');
    var found = false;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (!found) {
            if (line.len > 1 and line[line.len - 1] == ':') {
                const label = line[0 .. line.len - 1];
                // Mach-O prefixes C symbols with an underscore.
                const bare = if (label[0] == '_') label[1..] else label;
                found = std.mem.eql(u8, bare, symbol);
            }
            continue;
        }
        for ([_][]const u8{ ".quad", ".xword", ".8byte" }) |directive| {
            if (std.mem.startsWith(u8, line, directive)) {
                // Drop the operand list's trailing comment (`; 0xa0`, `# ...`).
                var operands = std.mem.tokenizeAny(u8, line[directive.len..], " \t");
                return std.fmt.parseInt(u64, operands.next() orelse return error.ProbeValueNotFound, 0);
            }
        }
    }
    std.debug.print("probe symbol {s} not found in assembly\n", .{symbol});
    return error.ProbeValueNotFound;
}
