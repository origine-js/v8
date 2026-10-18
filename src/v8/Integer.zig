const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const MaybeHandle = v8.MaybeHandle;
const Isolate = v8.Isolate;
const Context = v8.Context;
const String = v8.String;
const Value = v8.Value;
const Number = v8.Number;

pub const Integer = extern struct {
    number: Number,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .number = Number.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, v: i32) @This() {
        return from_opaque(e.v8__Integer__New(isolate.handle, v)).?;
    }

    pub fn initFromUnsigned(isolate: Isolate, v: u32) @This() {
        return from_opaque(e.v8__Integer__NewFromUnsigned(isolate.handle, v)).?;
    }

    pub fn value(self: @This()) i64 {
        return e.v8__Integer__Value(self);
    }
};
