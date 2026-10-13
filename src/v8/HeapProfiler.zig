const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;

pub const HeapProfiler = struct {
    /// Receives snapshot chunks; return false to abort serialization.
    pub const OutputCallback = *const fn (arg: ?*anyopaque, data: ?[*]const u8, size: usize) callconv(.c) bool;

    /// Takes a heap snapshot and streams its JSON serialization to `callback`.
    pub fn takeHeapSnapshot(isolate: Isolate, callback: OutputCallback, arg: ?*anyopaque) void {
        e.v8__HeapProfiler__TakeHeapSnapshot(isolate.handle, callback, arg);
    }
};
