//! Generates `src/externs.gen.zig`: one `pub extern fn` per `v8__*` shim
//! defined in binding.cc, with ABI-exact Zig types (see types.zig).

const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const Clang = @import("clang.zig");
const Mapper = @import("types.zig");

pub const TypeMap = struct {
    /// Zig declarations copied verbatim into the generated `support` namespace.
    decls: []const []const u8,
    /// C++ type spelling (as clang prints it) -> Zig type expression.
    types: []const Mapper.Override,
};

pub const Stats = struct { emitted: usize, unmapped: usize };

/// Comptime helpers the generated signatures use to reuse v8.zig's own types.
/// Everything is ABI-checked, so a wrapper with the wrong shape is never picked
/// silently.
const helpers =
    \\const std = @import("std");
    \\const v8 = @import("v8.zig");
    \\
    \\/// The type v8.zig declares for `name`: `v8.<name>`, else the nested path
    \\/// (`Isolate_CreateParams` -> `v8.Isolate.CreateParams`), else the last
    \\/// component (`Promise_Resolver` -> `v8.Resolver`).
    \\fn lookup(comptime name: []const u8) ?type {
    \\    if (declared(v8, name)) |T| return T;
    \\    comptime var scope: type = v8;
    \\    comptime var rest: []const u8 = name;
    \\    inline while (std.mem.indexOfScalar(u8, rest, '_')) |i| {
    \\        scope = declared(scope, rest[0..i]) orelse break;
    \\        rest = rest[i + 1 ..];
    \\    } else if (declared(scope, rest)) |T| return T;
    \\    if (std.mem.lastIndexOfScalar(u8, name, '_')) |i| {
    \\        if (declared(v8, name[i + 1 ..])) |T| return T;
    \\    }
    \\    return null;
    \\}
    \\
    \\fn declared(comptime scope: type, comptime name: []const u8) ?type {
    \\    if (@typeInfo(scope) != .@"struct" or !@hasDecl(scope, name)) return null;
    \\    const decl = @field(scope, name);
    \\    return if (@TypeOf(decl) == type) decl else null;
    \\}
    \\
    \\/// A type v8.zig defines for an enum or callback typedef, checked to have the
    \\/// same size as the C++ type; otherwise `Fallback`.
    \\/// A C++ function pointer may be null, so a non-optional pointer type in v8.zig
    \\/// becomes optional when the C++ side is.
    \\fn Named(comptime name: []const u8, comptime Fallback: type) type {
    \\    const Found = lookup(name) orelse return Fallback;
    \\    const T = if (@typeInfo(Found) == .pointer and @typeInfo(Fallback) == .optional) ?Found else Found;
    \\    if (@sizeOf(T) != @sizeOf(Fallback)) {
    \\        @compileError(std.fmt.comptimePrint("v8.{s} is {d} bytes but the C++ type `{s}` is {d}", .{ name, @sizeOf(T), name, @sizeOf(Fallback) }));
    \\    }
    \\    return T;
    \\}
    \\
    \\/// Whether `T` is a handle wrapper: an extern struct that is exactly one pointer
    \\/// (possibly nested), so passing it by value is ABI-identical to passing the
    \\/// pointer. Value types such as `extern struct { inner: [8]u8 }` are not.
    \\fn isHandle(comptime T: type) bool {
    \\    switch (@typeInfo(T)) {
    \\        .pointer => return true,
    \\        .optional => |info| return isHandle(info.child),
    \\        .@"struct" => |info| {
    \\            if (info.layout != .@"extern" or info.field_types.len != 1) return false;
    \\            return isHandle(info.field_types[0]);
    \\        },
    \\        else => return false,
    \\    }
    \\}
    \\
    \\/// `const v8::T &` / `Local<T>`: v8.zig's handle wrapper by value, or a
    \\/// pointer to v8.zig's own extern struct, or a pointer to the opaque class.
    \\fn Ref(comptime name: []const u8) type {
    \\    if (lookup(name)) |T| {
    \\        if (isHandle(T)) return T;
    \\        // An extern wrapper is layout-identical to the C++ object: point at it.
    \\        if (@typeInfo(T) == .@"struct" and @typeInfo(T).@"struct".layout == .@"extern") return *const T;
    \\        // Other wrappers that declare `Opaque` are passed as `*T.Opaque` (Message, TryCatch, ...).
    \\        if (@typeInfo(T) == .@"struct" and @hasDecl(T, "Opaque")) return *const T.Opaque;
    \\    }
    \\    return *const @field(types, name);
    \\}
    \\
    \\/// `T *`: a pointer to the wrapper's `Opaque` if it has one, a pointer to v8.zig's
    \\/// own extern struct if it is a plain value type, else a generic handle.
    \\/// `uninit_t<T> *` (construct-in-place storage) points at the wrapped type `T`.
    \\fn Ptr(comptime raw_name: []const u8, comptime is_const: bool) type {
    \\    const name = if (std.mem.startsWith(u8, raw_name, "uninit_t_")) raw_name["uninit_t_".len..] else raw_name;
    \\    if (lookup(name)) |T| {
    \\        if (@typeInfo(T) == .@"struct" and !@hasDecl(T, "Opaque") and
    \\            @typeInfo(T).@"struct".layout == .@"extern" and !isHandle(T))
    \\        {
    \\            return if (is_const) ?*const T else ?*T;
    \\        }
    \\        if (@typeInfo(T) == .@"struct" and @hasDecl(T, "Opaque")) {
    \\            const O = T.Opaque;
    \\            return if (is_const) ?*const O else ?*O;
    \\        }
    \\    }
    \\    return v8.MaybeHandle;
    \\}
    \\
;

pub fn generate(
    arena: std.mem.Allocator,
    clang: Clang,
    includes: []const []const u8,
    typemap: TypeMap,
    out: *Io.Writer.Allocating,
) !Stats {
    const dump = try clang.astDump("v8__");
    const funcs = try ast.parse(arena, dump);

    var mapper: Mapper = .{ .arena = arena, .overrides = typemap.types };

    // Learn which by-value type names are enums (and how wide).
    const candidates = try mapper.enumCandidates(funcs);
    if (candidates.len != 0) {
        var prelude: Io.Writer.Allocating = .init(arena);
        for (includes) |inc| try prelude.writer.print("#include \"{s}\"\n", .{inc});
        try prelude.writer.writeAll(
            \\template <class T> constexpr uint64_t bg_kind() {
            \\  if constexpr (std::is_enum_v<T>) return 1 | ((uint64_t)sizeof(T) << 8) | (std::is_signed_v<std::underlying_type_t<T>> ? 2 : 0);
            \\  else return 0;
            \\}
            \\
        );
        const probes = try arena.alloc(Clang.Probe, candidates.len);
        for (candidates, probes, 0..) |name, *p, i| p.* = .{
            .name = try std.fmt.allocPrint(arena, "kind_{d}", .{i}),
            .expr = try std.fmt.allocPrint(arena, "bg_kind<{s}>()", .{name}),
        };
        const kinds = try clang.measure("externs_probe", prelude.written(), probes);
        for (candidates, kinds) |name, kind| try mapper.setKind(name, kind);
    }

    var body: Io.Writer.Allocating = .init(arena);
    var unmapped: Io.Writer.Allocating = .init(arena);
    var stats: Stats = .{ .emitted = 0, .unmapped = 0 };

    for (funcs) |f| {
        const line = renderFunc(arena, &mapper, f) catch |err| switch (err) {
            error.Unmapped => {
                stats.unmapped += 1;
                try unmapped.writer.print("// {s}: {s}\n", .{ f.name, mapper.reason });
                continue;
            },
            else => return err,
        };
        stats.emitted += 1;
        try body.writer.print("/// {s}\npub extern fn {s}\n\n", .{ f.signature, line });
    }

    const w = &out.writer;
    try w.writeAll("//! Generated by tools/bindgen (`zig build gen`) from binding/binding.cc - DO NOT EDIT.\n");
    try w.writeAll("//! Hand-written overrides for special types live in build-tools/typemap.zon.\n\n");
    try w.writeAll(helpers);

    try w.writeAll("/// Opaque handles for V8 classes; only ever used behind pointers.\npub const types = struct {\n");
    try writeSorted(arena, w, mapper.classes.keys(), "    pub const {s} = opaque {{}};\n");
    try w.writeAll("};\n\n/// Fixed-width integers matching the C++ enums' underlying types.\npub const enums = struct {\n");
    const enum_names = mapper.enums.keys();
    {
        const sorted = try arena.dupe([]const u8, enum_names);
        std.mem.sort([]const u8, sorted, {}, lessThan);
        for (sorted) |n| try w.print("    pub const {s} = {s};\n", .{ n, mapper.enums.get(n).? });
    }
    try w.writeAll("};\n\n/// Special types from build-tools/typemap.zon.\npub const support = struct {\n");
    for (typemap.decls) |d| try w.print("    {s}\n", .{d});
    try w.writeAll("};\n\n");

    try w.writeAll(body.written());
    try w.writeAll(
        \\test "every generated extern resolves against v8.zig" {
        \\    std.testing.refAllDecls(@This());
        \\}
        \\
        \\
    );

    if (mapper.degraded.count() != 0) {
        try w.writeAll("// Callback typedefs emitted as `?*const anyopaque` (ABI-identical; add a typemap.zon entry for a typed pointer):\n");
        var it = mapper.degraded.iterator();
        while (it.next()) |e| try w.print("//   {s}: {s}\n", .{ e.key_ptr.*, e.value_ptr.* });
        try w.writeAll("\n");
    }
    if (stats.unmapped != 0) {
        try w.writeAll("// Not generated (add a typemap.zon entry to enable):\n");
        try w.writeAll(unmapped.written());
    }
    return stats;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn writeSorted(arena: std.mem.Allocator, w: *Io.Writer, names: []const []const u8, comptime fmt: []const u8) !void {
    const sorted = try arena.dupe([]const u8, names);
    std.mem.sort([]const u8, sorted, {}, lessThan);
    for (sorted) |n| try w.print(fmt, .{n});
}

/// `name(a: T, b: U) R;`
fn renderFunc(arena: std.mem.Allocator, mapper: *Mapper, f: ast.Func) Mapper.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, f.name);
    try out.append(arena, '(');
    for (f.params, 0..) |p, i| {
        if (i != 0) try out.appendSlice(arena, ", ");
        const ty = mapper.typeOf(p.ty) catch |err| {
            if (err == error.Unmapped) {
                mapper.reason = try std.fmt.allocPrint(arena, "parameter {d}: {s}", .{ i, mapper.reason });
            }
            return err;
        };
        try out.appendSlice(arena, try paramName(arena, p.name, i));
        try out.appendSlice(arena, ": ");
        try out.appendSlice(arena, ty);
    }
    const ret = mapper.typeOf(f.ret) catch |err| {
        if (err == error.Unmapped) {
            mapper.reason = try std.fmt.allocPrint(arena, "return: {s}", .{mapper.reason});
        }
        return err;
    };
    try out.appendSlice(arena, ") ");
    try out.appendSlice(arena, ret);
    try out.append(arena, ';');
    return out.items;
}

fn paramName(arena: std.mem.Allocator, name: ?[]const u8, index: usize) ![]const u8 {
    const n = name orelse return std.fmt.allocPrint(arena, "arg{d}", .{index});
    const reserved = [_][]const u8{ "types", "enums", "support" };
    for (reserved) |r| if (std.mem.eql(u8, n, r)) return std.fmt.allocPrint(arena, "{s}_", .{n});
    if (!std.zig.isValidId(n)) return std.fmt.allocPrint(arena, "@\"{s}\"", .{n});
    return n;
}
