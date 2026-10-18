const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;

pub const Platform = struct {
    pub const Opaque = opaque {};

    handle: *Opaque,

    const Self = @This();

    /// Returns a new instance of the default v8::Platform implementation.
    /// |thread_pool_size| is the number of worker threads to allocate for background jobs.
    /// If 0, a suitable default based on the processors will be chosen.
    pub fn initDefault(thread_pool_size: u32, idle_task_support: bool) Self {
        return .{
            .handle = e.v8__Platform__NewDefaultPlatform(@as(c_int, @intCast(thread_pool_size)), idle_task_support).?,
        };
    }

    /// Like `initDefault`, but without memory protection keys on worker threads.
    pub fn initUnprotectedDefault(thread_pool_size: u32, idle_task_support: bool) Self {
        return .{
            .handle = e.v8__Platform__NewUnprotectedDefaultPlatform(@as(c_int, @intCast(thread_pool_size)), idle_task_support).?,
        };
    }

    /// A platform that runs all tasks on the calling thread (via `pumpMessageLoop`).
    pub fn initSingleThreaded(idle_task_support: bool) Self {
        return .{
            .handle = e.v8__Platform__NewSingleThreadedDefaultPlatform(idle_task_support).?,
        };
    }

    pub fn deinit(self: Self) void {
        e.v8__Platform__DELETE(self.handle);
    }

    /// Pumps the message loop for the given isolate.
    pub fn pumpMessageLoop(self: Self, isolate: Isolate, wait_for_work: bool) bool {
        return e.v8__Platform__PumpMessageLoop(self.handle, isolate.handle, wait_for_work);
    }

    /// Runs idle tasks for the isolate for up to `idle_time_in_seconds`.
    pub fn runIdleTasks(self: Self, isolate: Isolate, idle_time_in_seconds: f64) void {
        e.v8__Platform__RunIdleTasks(self.handle, isolate.handle, idle_time_in_seconds);
    }

    /// Must be called before the isolate is disposed.
    pub fn notifyIsolateShutdown(self: Self, isolate: Isolate) void {
        e.v8__Platform__NotifyIsolateShutdown(self.handle, isolate.handle);
    }
};
