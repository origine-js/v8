const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const Function = v8.Function;
const MicrotasksPolicy = v8.MicrotasksPolicy;

pub const MicrotaskQueue = struct {
    pub const Opaque = opaque {};

    handle: *Opaque,

    const Self = @This();

    pub fn init(isolate: Isolate, policy: MicrotasksPolicy) Self {
        return .{ .handle = e.v8__MicrotaskQueue__New(isolate.handle, policy).? };
    }

    /// Runs the queue's destructor. The shim does not release the storage itself.
    pub fn deinit(self: Self) void {
        e.v8__MicrotaskQueue__DESTRUCT(self.handle);
    }

    pub fn performCheckpoint(self: Self, isolate: Isolate) void {
        e.v8__MicrotaskQueue__PerformCheckpoint(isolate.handle, self.handle);
    }

    pub fn isRunningMicrotasks(self: Self) bool {
        return e.v8__MicrotaskQueue__IsRunningMicrotasks(self.handle);
    }

    pub fn getMicrotasksScopeDepth(self: Self) c_int {
        return e.v8__MicrotaskQueue__GetMicrotasksScopeDepth(self.handle);
    }

    pub fn enqueueMicrotask(self: Self, isolate: Isolate, callback: Function) void {
        e.v8__MicrotaskQueue__EnqueueMicrotask(isolate.handle, self.handle, callback.object.value.data.handle);
    }
};
