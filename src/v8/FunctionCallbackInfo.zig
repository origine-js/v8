const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const ReturnValue = v8.ReturnValue;
const Data = v8.Data;
const Value = v8.Value;
const Object = v8.Object;

pub const FunctionCallbackInfo = extern struct {
    pub const Opaque = opaque {};

    inner: *Opaque,

    pub fn data(self: @This()) ?Data {
        return Data.from_opaque(e.v8__FunctionCallbackInfo__Data(self));
    }

    pub fn length(self: @This()) c_int {
        return e.v8__FunctionCallbackInfo__Length(self);
    }

    pub fn get_arg(self: @This(), index: c_int) Value {
        return Value.from_opaque(e.v8__FunctionCallbackInfo__Get(self, index)).?;
    }

    pub fn isolate(self: @This()) Isolate {
        return .{ .handle = e.v8__FunctionCallbackInfo__GetIsolate(self).? };
    }

    /// `true` when the function was invoked with `new`.
    pub fn isConstructCall(self: @This()) bool {
        return e.v8__FunctionCallbackInfo__IsConstructCall(self);
    }

    pub fn this(self: @This()) Object {
        return Object.from_opaque(e.v8__FunctionCallbackInfo__This(self)).?;
    }

    pub fn newTarget(self: @This()) Value {
        return Value.from_opaque(e.v8__FunctionCallbackInfo__NewTarget(self)).?;
    }

    pub fn retval(self: @This()) ReturnValue {
        return .{ .addr = @intFromPtr(e.v8__FunctionCallbackInfo__GetReturnValue(self)) };
    }
};
