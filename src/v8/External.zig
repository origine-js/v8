const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const MaybeHandle = v8.MaybeHandle;
const Value = v8.Value;

pub const External = extern struct {
    value: Value,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .value = Value.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, ptr: ?*anyopaque) @This() {
        return External.from_opaque(e.v8__External__New(isolate.handle, ptr)).?;
    }

    pub fn pointer(self: @This()) ?*anyopaque {
        return e.v8__External__Value(self);
    }
};
