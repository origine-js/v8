pub fn Maybe(comptime T: type) type {
    return extern struct {
        has_value: bool,
        value: T,

        pub fn as_optional(self: @This()) ?T {
            if (!self.has_value) return null;
            return self.value;
        }
        pub fn from_optional(opt: ?T) @This() {
            return .{
                .has_value = if (opt) |_| true else false,
                .value = if (opt) |v| v else undefined,
            };
        }
    };
}

pub const MaybeBool = enum(c_int) {
    JustFalse = 0,
    JustTrue = 1,
    Nothing = 2,

    pub fn from_optional(opt: ?bool) @This() {
        return switch (opt orelse return .Nothing) {
            true => .JustTrue,
            false => .JustFalse,
        };
    }

    pub fn as_optional(self: @This()) ?bool {
        return switch (self) {
            @This().JustFalse => false,
            @This().JustTrue => true,
            @This().Nothing => null,
        };
    }
};

/// Extract the native local handle from a wrapper's inheritance chain.
pub fn rawHandle(value: anytype) @import("../v8.zig").MaybeHandle {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer, .optional => return @ptrCast(value),
        .@"struct" => |info| {
            if (info.field_names.len != 1) @compileError("expected a local handle wrapper");
            return rawHandle(@field(value, info.field_names[0]));
        },
        else => @compileError("expected a local handle wrapper"),
    }
}
