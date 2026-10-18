const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const Function = v8.Function;
const MicrotasksPolicy = v8.MicrotasksPolicy;

/// Rooting handle for a queue created by `MicrotaskQueue.init`; only ever used behind a pointer.
pub const MicrotaskQueueHandle = struct {
    pub const Opaque = opaque {};
};

pub const MicrotaskQueue = struct {
    pub const Opaque = opaque {};

    /// Borrowed queue; valid while `root` is alive, or while an associated context is
    /// alive when V8 uses the default cppgc-managed queue.
    handle: *Opaque,
    /// Rooting handle owned by this value and released by `deinit`; null when the
    /// queue is borrowed (for example from `Context.getMicrotaskQueue`).
    root: ?*MicrotaskQueueHandle.Opaque = null,

    const Self = @This();

    /// Creates a queue rooted for `isolate`. Must run on the isolate's thread.
    /// The returned value owns its root; call `deinit` on the isolate thread
    /// before the isolate is disposed. Retains no input storage.
    pub fn init(isolate: Isolate, policy: MicrotasksPolicy) Self {
        const root = e.v8__MicrotaskQueueHandle__New(isolate.handle, policy).?;
        return .{ .handle = e.v8__MicrotaskQueueHandle__Get(root).?, .root = root };
    }

    /// Releases the root created by `init`; asserts the queue is not a borrowed view. With the default cppgc-managed queue, contexts
    /// associated with the queue keep it alive afterwards; otherwise the queue is deleted
    /// here and must outlive no associated context. Must precede isolate disposal.
    pub fn deinit(self: Self) void {
        e.v8__MicrotaskQueueHandle__DELETE(self.root.?);
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
