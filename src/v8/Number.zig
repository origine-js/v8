const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const MaybeHandle = v8.MaybeHandle;
const Value = v8.Value;
const Numeric = v8.Numeric;

pub const Number = extern struct {
    numeric: Numeric,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .numeric = Numeric.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, value: f64) @This() {
        return @This().from_opaque(e.v8__Number__New(isolate.handle, value)).?;
    }

    pub fn initInt(isolate: Isolate, value: i32) @This() {
        return @This().from_opaque(e.v8__Number__NewInt(isolate.handle, value)).?;
    }

    pub fn initUInt(isolate: Isolate, value: u32) @This() {
        return @This().from_opaque(e.v8__Number__NewUInt(isolate.handle, value)).?;
    }

    pub fn Value(self: @This()) f64 {
        return e.v8__Number__Value(self);
    }
};
