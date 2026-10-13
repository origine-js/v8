const binding = @import("../binding.zig");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const Context = v8.Context;
const Value = v8.Value;
const Message = v8.Message;

pub const TryCatch = struct {
    pub const Opaque = [binding.sizes.TryCatch]u8;

    inner: Opaque,

    const Self = @This();

    pub fn init(self: *Self, isolate: Isolate) void {
        e.v8__TryCatch__CONSTRUCT(&self.inner, isolate.handle);
    }

    pub fn deinit(self: *Self) void {
        e.v8__TryCatch__DESTRUCT(&self.inner);
    }

    pub fn hasCaught(self: *const Self) bool {
        return e.v8__TryCatch__HasCaught(&self.inner);
    }

    pub fn canContinue(self: *const Self) bool {
        return e.v8__TryCatch__CanContinue(&self.inner);
    }

    pub fn hasTerminated(self: *const Self) bool {
        return e.v8__TryCatch__HasTerminated(&self.inner);
    }

    pub fn getException(self: *const Self) ?Value {
        const handle = e.v8__TryCatch__Exception(&self.inner) orelse return null;
        return .from_opaque(handle);
    }

    pub fn getStackTrace(self: *const Self, context: Context) ?Value {
        const handle = e.v8__TryCatch__StackTrace(&self.inner, context) orelse return null;
        return .from_opaque(handle);
    }

    pub fn getMessage(self: *const Self) ?Message {
        const handle = e.v8__TryCatch__Message(&self.inner) orelse return null;
        return .{ .handle = handle };
    }

    pub fn reset(self: *Self) void {
        e.v8__TryCatch__Reset(&self.inner);
    }

    pub fn reThrow(self: *Self) ?Value {
        const handle = e.v8__TryCatch__ReThrow(&self.inner) orelse return null;
        return .from_opaque(handle);
    }

    pub fn isVerbose(self: *const Self) bool {
        return e.v8__TryCatch__IsVerbose(&self.inner);
    }

    pub fn setVerbose(self: *Self, value: bool) void {
        e.v8__TryCatch__SetVerbose(&self.inner, value);
    }

    pub fn setCaptureMessage(self: *Self, value: bool) void {
        e.v8__TryCatch__SetCaptureMessage(&self.inner, value);
    }
};
