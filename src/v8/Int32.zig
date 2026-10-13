const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const MaybeHandle = v8.MaybeHandle;
const Isolate = v8.Isolate;
const Context = v8.Context;
const String = v8.String;
const Value = v8.Value;
const Integer = v8.Integer;

pub const Int32 = extern struct {
    integer: Integer,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .integer = Integer.from_opaque(o) orelse return null };
    }

    pub fn value(self: @This()) i32 {
        return e.v8__Int32__Value(self);
    }
};
