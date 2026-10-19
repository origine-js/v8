//! Reads `clang -Xclang -ast-dump=json` output for the `v8__*` and `simdutf__*` shims.
//!
//! With `-ast-dump-filter` clang prints one pretty-printed top-level JSON
//! object per matching declaration, each closed by a `}` at column 0, so the
//! stream is split on those lines and every chunk is parsed on its own.

const std = @import("std");

pub const TypeRef = struct {
    /// As written, e.g. `const v8::Object &`.
    q: []const u8,
    /// Set for typedefs/aliases, e.g. `void (*)(char *, size_t)`.
    desugared: ?[]const u8 = null,
};

pub const Param = struct {
    name: ?[]const u8,
    ty: TypeRef,
};

pub const Func = struct {
    name: []const u8,
    ret: TypeRef,
    params: []const Param,
    /// `R (P1, P2)` as clang prints it, used for documentation comments.
    signature: []const u8,
};

const Type = struct {
    qualType: []const u8,
    desugaredQualType: ?[]const u8 = null,
};

const Node = struct {
    kind: []const u8 = "",
    name: ?[]const u8 = null,
    mangledName: ?[]const u8 = null,
    storageClass: ?[]const u8 = null,
    type: ?Type = null,
    inner: ?[]const Node = null,
};

pub fn parse(arena: std.mem.Allocator, dump: []const u8) ![]const Func {
    var funcs: std.ArrayList(Func) = .empty;

    var start: usize = 0;
    var pos: usize = 0;
    while (pos < dump.len) {
        const eol = std.mem.indexOfScalarPos(u8, dump, pos, '\n') orelse dump.len;
        const line = dump[pos..eol];
        if (std.mem.eql(u8, line, "}")) {
            const chunk = dump[start..eol];
            try addNode(arena, &funcs, chunk);
            start = @min(eol + 1, dump.len);
        }
        pos = eol + 1;
    }
    return funcs.items;
}

fn addNode(arena: std.mem.Allocator, funcs: *std.ArrayList(Func), chunk: []const u8) !void {
    const node = try std.json.parseFromSliceLeaky(Node, arena, chunk, .{ .ignore_unknown_fields = true });
    if (!std.mem.eql(u8, node.kind, "FunctionDecl")) return;
    const name = node.name orelse return;
    if (!isShim(name)) return;
    // Only extern "C" functions (unmangled), never static helpers.
    const mangled = node.mangledName orelse return;
    if (!(std.mem.eql(u8, mangled, name) or (mangled.len == name.len + 1 and mangled[0] == '_' and std.mem.eql(u8, mangled[1..], name)))) return;
    if (node.storageClass != null) return;
    const fn_type = (node.type orelse return).qualType;

    var params: std.ArrayList(Param) = .empty;
    for (node.inner orelse &.{}) |child| {
        if (!std.mem.eql(u8, child.kind, "ParmVarDecl")) continue;
        const t = child.type orelse return;
        try params.append(arena, .{
            .name = child.name,
            .ty = .{ .q = t.qualType, .desugared = t.desugaredQualType },
        });
    }

    try funcs.append(arena, .{
        .name = name,
        .ret = .{ .q = std.mem.trim(u8, fn_type[0..returnTypeEnd(fn_type)], " ") },
        .params = params.items,
        .signature = fn_type,
    });
}

/// Whether `name` is one of the extern "C" shim families the generator covers:
/// `v8__*` and the simdutf bridge `simdutf__*`. Accepts and returns values only.
pub fn isShim(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "v8__") or std.mem.startsWith(u8, name, "simdutf__");
}

/// Index of the `(` that opens the parameter list: the first one outside of
/// template angle brackets.
fn returnTypeEnd(fn_type: []const u8) usize {
    var depth: usize = 0;
    for (fn_type, 0..) |c, i| switch (c) {
        '<' => depth += 1,
        '>' => depth -|= 1,
        '(' => if (depth == 0) return i,
        else => {},
    };
    return fn_type.len;
}
