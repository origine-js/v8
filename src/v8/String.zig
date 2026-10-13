const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const MaybeHandle = v8.MaybeHandle;
const Name = v8.Name;

pub const String = extern struct {
    pub const NewStringType = enum(c_int) { Normal, Internalized };

    pub const WriteFlags = struct {
        pub const None = @as(c_int, 0);
        pub const NullTermination = @as(c_int, 1) << 0;
        pub const PreserveAsciiNull = @as(c_int, 1) << 1;
        pub const ReplaceInvalidUtf8 = @as(c_int, 1) << 2;
    };

    name: Name,

    const Self = @This();

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .name = Name.from_opaque(o) orelse return null };
    }

    pub fn initUtf8(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewFromUtf8(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn initOneByte(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewFromOneByte(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn initTwoByte(isolate: Isolate, str: []const u16) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewFromTwoByte(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn initOneByteStatic(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewExternalOneByteStatic(isolate.handle, str.ptr, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn initTwoByteStatic(isolate: Isolate, str: []const u16) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewExternalTwoByteStatic(isolate.handle, str.ptr, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn len(self: Self) c_int {
        return e.v8__String__Length(self);
    }

    pub fn lenUtf8(self: Self, isolate: Isolate) usize {
        return e.v8__String__Utf8Length(self, isolate.handle);
    }

    pub fn writeUtf8(self: Self, isolate: Isolate, buf: []u8) usize {
        const flags = WriteFlags.ReplaceInvalidUtf8;
        return e.v8__String__WriteUtf8(self, isolate.handle, buf.ptr, buf.len, flags, null);
    }

    pub fn empty(isolate: v8.Isolate) ?v8.String {
        return v8.String.from_opaque(e.v8__String__Empty(isolate.handle));
    }

    pub fn write(self: v8.String, isolate: v8.Isolate, offset: u32, length: u32, buffer: ?[*]u16, flags: c_int) void {
        e.v8__String__Write(self, isolate.handle, offset, length, buffer, flags);
    }

    pub fn writeOneByte(self: v8.String, isolate: v8.Isolate, offset: u32, length: u32, buffer: ?[*]u8, flags: c_int) void {
        e.v8__String__WriteOneByte(self, isolate.handle, offset, length, buffer, flags);
    }

    pub fn getExternalStringResource(self: v8.String) @typeInfo(@TypeOf(e.v8__String__GetExternalStringResource)).@"fn".return_type.? {
        return e.v8__String__GetExternalStringResource(self);
    }

    pub fn getExternalStringResourceBase(self: v8.String, encoding_out: @typeInfo(@TypeOf(e.v8__String__GetExternalStringResourceBase)).@"fn".param_types[1].?) @typeInfo(@TypeOf(e.v8__String__GetExternalStringResourceBase)).@"fn".return_type.? {
        return e.v8__String__GetExternalStringResourceBase(self, encoding_out);
    }

    pub fn newExternalOneByteConst(isolate: v8.Isolate, resource: ?v8.ExternalOneByteStringResource) ?v8.String {
        return v8.String.from_opaque(e.v8__String__NewExternalOneByteConst(isolate.handle, if (resource) |v| v.handle else null));
    }

    pub fn newExternalOneByte(isolate: v8.Isolate, data: ?[*]u8, length: c_int, deinit: v8.Callbacks.ExternalOneByteString_ZigDeinit) ?v8.String {
        return v8.String.from_opaque(e.v8__String__NewExternalOneByte(isolate.handle, data, length, deinit));
    }

    pub fn isExternal(self: v8.String) bool {
        return e.v8__String__IsExternal(self);
    }

    pub fn isExternalOneByte(self: v8.String) bool {
        return e.v8__String__IsExternalOneByte(self);
    }

    pub fn isExternalTwoByte(self: v8.String) bool {
        return e.v8__String__IsExternalTwoByte(self);
    }

    pub fn isOneByte(self: v8.String) bool {
        return e.v8__String__IsOneByte(self);
    }

    pub fn containsOnlyOneByte(self: v8.String) bool {
        return e.v8__String__ContainsOnlyOneByte(self);
    }
    /// Borrows string storage and prevents garbage collection. Construct at its final
    /// address, do not copy, and deinit before leaving the current HandleScope.
    pub const ValueView = extern struct {
        storage: [@import("../binding.zig").sizes.String_ValueView]u8 align(@alignOf(usize)),
        pub fn init(self: *@This(), isolate: v8.Isolate, string: v8.String) void {
            e.v8__String__ValueView__CONSTRUCT(self, isolate.handle, string);
        }
        pub fn deinit(self: *@This()) void {
            e.v8__String__ValueView__DESTRUCT(self);
        }
        pub fn isOneByte(self: *const @This()) bool {
            return e.v8__String__ValueView__is_one_byte(self);
        }
        pub fn data(self: *const @This()) ?*const anyopaque {
            return e.v8__String__ValueView__data(self);
        }
        pub fn len(self: *const @This()) usize {
            return @intCast(e.v8__String__ValueView__length(self));
        }
        pub fn bytes(self: *const @This()) ?[]const u8 {
            if (!self.isOneByte()) return null;
            if (self.len() == 0) return &.{};
            return @as([*]const u8, @ptrCast(self.data().?))[0..self.len()];
        }
        pub fn words(self: *const @This()) ?[]const u16 {
            if (self.isOneByte()) return null;
            if (self.len() == 0) return &.{};
            return @as([*]const u16, @ptrCast(@alignCast(self.data().?)))[0..self.len()];
        }
    };
};
