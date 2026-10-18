const std = @import("std");
const binding = @import("../generated/binding.zig");
const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const ReturnValue = v8.ReturnValue;
const Data = v8.Data;
const Object = v8.Object;

pub const PropertyCallbackInfo = extern struct {
    pub const Opaque = [binding.sizes.PropertyCallbackInfo]u8;

    inner: Opaque,

    pub fn isolate(self: *const @This()) Isolate {
        return .{ .handle = e.v8__PropertyCallbackInfo__GetIsolate(self).? };
    }

    pub fn data(self: *const @This()) ?Data {
        return Data.from_opaque(e.v8__PropertyCallbackInfo__Data(self));
    }

    pub fn this(self: *const @This()) Object {
        return Object.from_opaque(e.v8__PropertyCallbackInfo__This(self)).?;
    }

    pub fn holder(self: *const @This()) Object {
        return Object.from_opaque(e.v8__PropertyCallbackInfo__Holder(self)).?;
    }

    pub fn retval(self: *const @This()) ReturnValue {
        return .{ .addr = @intFromPtr(e.v8__PropertyCallbackInfo__GetReturnValue(self)) };
    }

    pub fn shouldThrowOnError(self: *const @This()) bool {
        return e.v8__PropertyCallbackInfo__ShouldThrowOnError(self);
    }

    comptime {
        std.debug.assert(@sizeOf(PropertyCallbackInfo) == binding.sizes.PropertyCallbackInfo);
    }
};
