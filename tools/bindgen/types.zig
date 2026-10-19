//! Maps the C++ types used by the `v8__*` and `simdutf__*` shims to Zig types.
//!
//! Mapping is ABI driven and deliberately conservative: a type that cannot be
//! mapped with certainty makes its function "unmapped" (reported, not emitted)
//! instead of guessing a layout.
//!
//!   void / bool / ints / floats        -> Zig primitives
//!   const T&, Local<T>                 -> Ref("T")   v8.zig's by-value wrapper if it is
//!                                         pointer sized, else *const types.T
//!   T*                                 -> Ptr("T")   *v8.T.Opaque if v8.zig has one,
//!                                         else v8.MaybeHandle
//!   MaybeLocal<T>                      -> v8.MaybeHandle
//!   enums (probed with clang)          -> Named("E", u32)  v8.zig's enum if the size
//!                                         matches, else the fixed-width int
//!   typedef'd function pointers        -> Named("Cb", ?*const fn (...) callconv(.c) R)
//!   anything else                      -> typemap.zon override, or unmapped
//!
//! `Ref`, `Ptr` and `Named` are comptime helpers emitted at the top of the
//! generated file; they look types up in v8.zig, so the hand-written wrappers
//! keep their own conventions and every use is size-checked.

const std = @import("std");
const ast = @import("ast.zig");

const Mapper = @This();

pub const Override = struct { cpp: []const u8, zig: []const u8 };

arena: std.mem.Allocator,
overrides: []const Override,
/// Opaque class names referenced so far (sanitized), for the `types` namespace.
classes: std.array_hash_map.String(void) = .empty,
/// Enum name (sanitized) -> Zig integer type, filled from clang probes.
enums: std.array_hash_map.String([]const u8) = .empty,
/// Why the last `typeOf` call failed.
reason: []const u8 = "",
/// Callback typedefs that could not be typed precisely (name -> why). They are
/// emitted as `?*const anyopaque`, which is ABI-identical: every function
/// pointer is pointer sized.
degraded: std.array_hash_map.String([]const u8) = .empty,

pub const Error = error{ Unmapped, OutOfMemory };

const Ty = union(enum) {
    named: []const u8,
    ptr: Ptr,
    ref: Ptr,
    func: Func,

    const Ptr = struct { to: *const Ty, is_const: bool };
    const Func = struct { ret: *const Ty, params: []const Ty };
};

const Prim = struct { zig: []const u8, bytes: bool = false };

fn prim(name: []const u8) ?Prim {
    const table = std.StaticStringMap(Prim).initComptime(.{
        .{ "void", Prim{ .zig = "void" } },
        .{ "bool", Prim{ .zig = "bool" } },
        .{ "char", Prim{ .zig = "u8", .bytes = true } },
        .{ "signed char", Prim{ .zig = "i8" } },
        .{ "unsigned char", Prim{ .zig = "u8", .bytes = true } },
        .{ "short", Prim{ .zig = "c_short" } },
        .{ "unsigned short", Prim{ .zig = "c_ushort" } },
        .{ "int", Prim{ .zig = "c_int" } },
        .{ "unsigned int", Prim{ .zig = "c_uint" } },
        .{ "long", Prim{ .zig = "c_long" } },
        .{ "unsigned long", Prim{ .zig = "c_ulong" } },
        .{ "long long", Prim{ .zig = "c_longlong" } },
        .{ "unsigned long long", Prim{ .zig = "c_ulonglong" } },
        .{ "float", Prim{ .zig = "f32" } },
        .{ "double", Prim{ .zig = "f64" } },
        .{ "size_t", Prim{ .zig = "usize" } },
        .{ "ssize_t", Prim{ .zig = "isize" } },
        .{ "ptrdiff_t", Prim{ .zig = "isize" } },
        .{ "intptr_t", Prim{ .zig = "isize" } },
        .{ "uintptr_t", Prim{ .zig = "usize" } },
        .{ "int8_t", Prim{ .zig = "i8", .bytes = true } },
        .{ "uint8_t", Prim{ .zig = "u8", .bytes = true } },
        .{ "char16_t", Prim{ .zig = "u16", .bytes = true } },
        .{ "char32_t", Prim{ .zig = "u32", .bytes = true } },
        .{ "int16_t", Prim{ .zig = "i16" } },
        .{ "uint16_t", Prim{ .zig = "u16", .bytes = true } },
        .{ "int32_t", Prim{ .zig = "i32" } },
        .{ "uint32_t", Prim{ .zig = "u32" } },
        .{ "int64_t", Prim{ .zig = "i64" } },
        .{ "uint64_t", Prim{ .zig = "u64" } },
    });
    return table.get(name);
}

/// Names that must be probed with clang to learn whether they are enums.
/// Collected from top-level parameter/return types, which clang spells fully
/// qualified, so the names are valid in a probe translation unit.
pub fn enumCandidates(self: *Mapper, funcs: []const ast.Func) ![]const []const u8 {
    var set: std.array_hash_map.String(void) = .empty;
    for (funcs) |f| {
        try self.addCandidate(&set, f.ret);
        for (f.params) |p| try self.addCandidate(&set, p.ty);
    }
    return set.keys();
}

fn addCandidate(self: *Mapper, set: *std.array_hash_map.String(void), t: ast.TypeRef) !void {
    if (self.override(t.q) != null) return;
    if (t.desugared) |d| if (std.mem.indexOf(u8, d, "(*)") != null) return;
    const name = std.mem.trim(u8, t.q, " ");
    // Only plain by-value names can be enums.
    if (std.mem.endsWith(u8, name, "*") or std.mem.endsWith(u8, name, "&")) return;
    if (std.mem.indexOfScalar(u8, name, '<') != null) return;
    const bare = if (std.mem.startsWith(u8, name, "const ")) name[6..] else name;
    if (prim(bare) != null) return;
    try set.put(self.arena, bare, {});
}

/// Registers the probe result for `name` (as returned by `enumCandidates`).
/// `kind` is 0 for "not an enum", otherwise `1 | size << 8 | signed << 1`.
pub fn setKind(self: *Mapper, name: []const u8, kind: u64) !void {
    if (kind & 1 == 0) return;
    const size = (kind >> 8) & 0xff;
    const signed = kind & 2 != 0;
    const zig = switch (size) {
        1 => if (signed) "i8" else "u8",
        2 => if (signed) "i16" else "u16",
        4 => if (signed) "i32" else "u32",
        8 => if (signed) "i64" else "u64",
        else => return,
    };
    try self.enums.put(self.arena, try sanitize(self.arena, name), zig);
}

/// Zig spelling of one declared type, or `error.Unmapped` (see `reason`).
pub fn typeOf(self: *Mapper, t: ast.TypeRef) Error![]const u8 {
    if (self.override(t.q)) |zig| return zig;
    if (t.desugared) |d| if (std.mem.indexOf(u8, d, "(*)") != null) {
        const typed = self.mapCallback(t.q, d) catch |err| switch (err) {
            error.Unmapped => blk: {
                try self.degraded.put(self.arena, std.mem.trim(u8, t.q, " "), self.reason);
                break :blk "?*const anyopaque";
            },
            else => return err,
        };
        const short = try sanitize(self.arena, t.q);
        return std.fmt.allocPrint(self.arena, "Named(\"{s}\", {s})", .{ short, typed });
    };
    const ty = try self.parse(t.q, t.desugared);
    return self.map(ty);
}

fn mapCallback(self: *Mapper, q: []const u8, d: []const u8) Error![]const u8 {
    return self.map(try self.parse(q, d));
}

fn override(self: *Mapper, q: []const u8) ?[]const u8 {
    const key = std.mem.trim(u8, q, " ");
    for (self.overrides) |o| if (std.mem.eql(u8, o.cpp, key)) return o.zig;
    return null;
}

fn fail(self: *Mapper, comptime fmt: []const u8, args: anytype) Error {
    self.reason = std.fmt.allocPrint(self.arena, fmt, args) catch return error.OutOfMemory;
    return error.Unmapped;
}

// ---------------------------------------------------------------- parsing

fn parse(self: *Mapper, q: []const u8, desugared: ?[]const u8) Error!Ty {
    if (desugared) |d| if (std.mem.indexOf(u8, d, "(*)") != null) return self.parseFunc(d);
    const s = std.mem.trim(u8, q, " ");
    if (std.mem.endsWith(u8, s, "&")) return .{ .ref = try self.parsePointee(s[0 .. s.len - 1]) };
    if (std.mem.endsWith(u8, s, "*")) return .{ .ptr = try self.parsePointee(s[0 .. s.len - 1]) };
    const bare = if (std.mem.startsWith(u8, s, "const ")) s[6..] else s;
    return .{ .named = std.mem.trim(u8, bare, " ") };
}

/// `rest` is a pointee spelled with its qualifiers, e.g. `const v8::Name *const`.
fn parsePointee(self: *Mapper, rest: []const u8) Error!Ty.Ptr {
    var r = std.mem.trim(u8, rest, " ");
    var is_const = false;
    // `T *const` (clang prints no space after `*`) or `T const`: the pointee is
    // const-qualified; a leading `const` belongs to the inner type and is
    // handled when that is parsed.
    if (std.mem.endsWith(u8, r, "*const") or std.mem.endsWith(u8, r, " const")) {
        is_const = true;
        r = std.mem.trim(u8, r[0 .. r.len - 5], " ");
    } else if (std.mem.startsWith(u8, r, "const ")) {
        is_const = true;
        r = r[6..];
    }
    const to = try self.arena.create(Ty);
    to.* = try self.parse(r, null);
    return .{ .to = to, .is_const = is_const };
}

/// `R (*)(A, B)`
fn parseFunc(self: *Mapper, d: []const u8) Error!Ty {
    const open = std.mem.indexOf(u8, d, "(*)(") orelse return self.fail("odd function pointer `{s}`", .{d});
    const ret = try self.arena.create(Ty);
    ret.* = try self.parse(d[0..open], null);

    const args_src = d[open + 4 ..];
    const close = std.mem.lastIndexOfScalar(u8, args_src, ')') orelse return self.fail("odd function pointer `{s}`", .{d});
    var params: std.ArrayList(Ty) = .empty;
    var depth: usize = 0;
    var begin: usize = 0;
    const inner = args_src[0..close];
    for (inner, 0..) |c, i| {
        switch (c) {
            '<', '(' => depth += 1,
            '>', ')' => depth -|= 1,
            ',' => if (depth == 0) {
                try params.append(self.arena, try self.parse(inner[begin..i], null));
                begin = i + 1;
            },
            else => {},
        }
    }
    const last = std.mem.trim(u8, inner[begin..], " ");
    if (last.len != 0 and !std.mem.eql(u8, last, "void")) try params.append(self.arena, try self.parse(last, null));
    return .{ .func = .{ .ret = ret, .params = params.items } };
}

// ---------------------------------------------------------------- mapping

fn map(self: *Mapper, ty: Ty) Error![]const u8 {
    return switch (ty) {
        .named => |n| self.mapValue(n),
        .ptr => |p| self.mapPointer(p, true),
        .ref => |p| self.mapPointer(p, false),
        .func => |f| self.mapFunc(f),
    };
}

fn mapValue(self: *Mapper, name: []const u8) Error![]const u8 {
    if (self.override(name)) |zig| return zig;
    if (prim(name)) |p| return p.zig;
    if (templateArg(name, "Local")) |arg| return self.ref(arg);
    if (templateArg(name, "MaybeLocal")) |arg| {
        _ = try self.className(arg);
        return "v8.MaybeHandle";
    }
    if (self.enumType(name)) |zig| {
        const short = try sanitize(self.arena, name);
        return std.fmt.allocPrint(self.arena, "Named(\"{s}\", {s})", .{ short, zig });
    }
    return self.fail("by-value `{s}` has no typemap entry", .{name});
}

fn ref(self: *Mapper, class: []const u8) Error![]const u8 {
    const cls = try self.className(class);
    return std.fmt.allocPrint(self.arena, "Ref(\"{s}\")", .{cls});
}

fn mapPointer(self: *Mapper, p: Ty.Ptr, optional: bool) Error![]const u8 {
    const opt: []const u8 = if (optional) "?" else "";
    const q: []const u8 = if (p.is_const) "const " else "";
    switch (p.to.*) {
        .named => |n| {
            if (std.mem.eql(u8, n, "void")) return std.fmt.allocPrint(self.arena, "{s}*{s}anyopaque", .{ opt, q });
            if (prim(n)) |pr| {
                const many: []const u8 = if (pr.bytes) "[*]" else "*";
                return std.fmt.allocPrint(self.arena, "{s}{s}{s}{s}", .{ opt, many, q, pr.zig });
            }
            if (self.override(n)) |zig| return std.fmt.allocPrint(self.arena, "{s}*{s}{s}", .{ opt, q, zig });
            const cls = try self.className(n);
            if (self.enums.contains(cls)) return std.fmt.allocPrint(self.arena, "{s}*{s}enums.{s}", .{ opt, q, cls });
            if (!optional) return std.fmt.allocPrint(self.arena, "Ref(\"{s}\")", .{cls});
            return std.fmt.allocPrint(self.arena, "Ptr(\"{s}\", {})", .{ cls, p.is_const });
        },
        .ptr, .ref => {
            // Pointer to pointer: treat as an array of handles.
            const elem = try self.map(p.to.*);
            return std.fmt.allocPrint(self.arena, "{s}[*]{s}{s}", .{ opt, q, elem });
        },
        .func => return self.fail("pointer to function pointer", .{}),
    }
}

fn mapFunc(self: *Mapper, f: Ty.Func) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(self.arena, "?*const fn (");
    for (f.params, 0..) |param, i| {
        if (i != 0) try out.appendSlice(self.arena, ", ");
        try out.appendSlice(self.arena, try self.map(param));
    }
    try out.appendSlice(self.arena, ") callconv(.c) ");
    try out.appendSlice(self.arena, try self.map(f.ret.*));
    return out.items;
}

/// Registers `name` as an opaque class and returns its sanitized spelling.
fn className(self: *Mapper, name: []const u8) Error![]const u8 {
    const cls = try sanitize(self.arena, name);
    if (!self.enums.contains(cls)) try self.classes.put(self.arena, cls, {});
    return cls;
}

/// Enum lookup that also accepts the unqualified spelling clang uses inside
/// function-pointer typedefs (`GCType` for `v8::GCType`, `UseCounterFeature`
/// for `v8::Isolate::UseCounterFeature`).
fn enumType(self: *Mapper, name: []const u8) ?[]const u8 {
    const key = sanitize(self.arena, name) catch return null;
    if (self.enums.get(key)) |zig| return zig;
    var found: ?[]const u8 = null;
    var it = self.enums.iterator();
    while (it.next()) |e| {
        if (std.mem.endsWith(u8, e.key_ptr.*, key) and
            (e.key_ptr.len == key.len or e.key_ptr.*[e.key_ptr.len - key.len - 1] == '_'))
        {
            if (found != null) return null; // ambiguous
            found = e.value_ptr.*;
        }
    }
    return found;
}

/// `Local<v8::Value>` -> `v8::Value` (also accepts `v8::Local<...>`).
fn templateArg(name: []const u8, template: []const u8) ?[]const u8 {
    var s = name;
    if (std.mem.startsWith(u8, s, "v8::")) s = s[4..];
    if (!std.mem.startsWith(u8, s, template)) return null;
    s = s[template.len..];
    if (s.len < 2 or s[0] != '<' or s[s.len - 1] != '>') return null;
    return std.mem.trim(u8, s[1 .. s.len - 1], " ");
}

/// Identifier for a C++ type name: drops `v8::`, `<v8::Value>` and punctuation.
pub fn sanitize(arena: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    var s = try std.mem.replaceOwned(u8, arena, name, "<v8::Value>", "");
    s = try std.mem.replaceOwned(u8, arena, s, "v8::", "");
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| {
        const ok = std.ascii.isAlphanumeric(c);
        if (ok) {
            try out.append(arena, c);
        } else if (out.items.len != 0 and out.items[out.items.len - 1] != '_') {
            try out.append(arena, '_');
        }
    }
    while (out.items.len != 0 and out.items[out.items.len - 1] == '_') _ = out.pop();
    return out.items;
}
