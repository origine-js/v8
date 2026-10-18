const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;

/// `v8::WeakCallbackInfo<void>`, handed to the callback of `Global.newWeak`.
pub const WeakCallbackInfo = struct {
    pub const Opaque = opaque {};
    /// How the generated externs spell `WeakCallbackInfo<void>`.
    pub const @"void" = @This();

    pub const Callback = *const fn (*const Opaque) callconv(.c) void;

    handle: *const Opaque,

    const Self = @This();

    pub fn getIsolate(self: Self) Isolate {
        return .{ .handle = e.v8__WeakCallbackInfo__GetIsolate(self.handle).? };
    }

    pub fn getParameter(self: Self) ?*anyopaque {
        return e.v8__WeakCallbackInfo__GetParameter(self.handle);
    }

    /// Schedules `callback` to run after the first pass; it may call into V8.
    pub fn setSecondPassCallback(self: Self, callback: Callback) void {
        e.v8__WeakCallbackInfo__SetSecondPassCallback(self.handle, callback);
    }
};
