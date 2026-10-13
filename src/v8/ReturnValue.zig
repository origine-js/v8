const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Value = v8.Value;

pub const ReturnValue = extern struct {
    addr: usize,

    pub fn set(self: *@This(), value: Value) void {
        e.v8__ReturnValue__Value__Set(self, value);
    }

    pub fn setBool(self: *@This(), i: bool) void {
        e.v8__ReturnValue__Value__Set__Bool(self, i);
    }

    pub fn setInt32(self: *@This(), i: i32) void {
        e.v8__ReturnValue__Value__Set__Int32(self, i);
    }

    pub fn setUint32(self: *@This(), i: u32) void {
        e.v8__ReturnValue__Value__Set__Uint32(self, i);
    }

    pub fn setDouble(self: *@This(), i: f64) void {
        e.v8__ReturnValue__Value__Set__Double(self, i);
    }

    pub fn setNull(self: *@This()) void {
        e.v8__ReturnValue__Value__SetNull(self);
    }

    pub fn setUndefined(self: *@This()) void {
        e.v8__ReturnValue__Value__SetUndefined(self);
    }

    pub fn setEmptyString(self: *@This()) void {
        e.v8__ReturnValue__Value__SetEmptyString(self);
    }

    pub fn get(self: *const @This()) ?Value {
        return Value.from_opaque(e.v8__ReturnValue__Value__Get(self));
    }
};
