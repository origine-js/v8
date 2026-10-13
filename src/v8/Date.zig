const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const MaybeHandle = v8.MaybeHandle;
const Isolate = v8.Isolate;
const Context = v8.Context;
const String = v8.String;
const Value = v8.Value;
const Object = v8.Object;

pub const Date = extern struct {
    object: Object,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .object = Object.from_opaque(o) orelse return null };
    }

    pub fn init(context: Context, time: f64) ?@This() {
        return from_opaque(e.v8__Date__New(context, time));
    }

    pub fn valueOf(self: @This()) f64 {
        return e.v8__Date__ValueOf(self);
    }
};
