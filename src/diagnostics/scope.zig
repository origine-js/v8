//! Optional, allocation-free scope initialization tracing on the calling thread.
const std = @import("std");
const stderr = @import("stderr.zig");
threadlocal var count: usize = 0;
threadlocal var samples: [64]struct { name: []const u8, ns: i64 } = undefined;

/// Reads the monotonic clock; retains no resources. Clock failure is fatal.
fn now() i64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts) != 0) @panic("startup clock failed");
    return @as(i64, @intCast(ts.sec)) * 1_000_000_000 + @as(i64, @intCast(ts.nsec));
}

/// Reads but does not retain environment storage. Returns a copied timestamp
/// when tracing is enabled, otherwise null; allocates nothing.
pub fn begin() ?i64 {
    return if (std.c.getenv("V8_STARTUP_TRACE") != null) now() else null;
}

/// Borrows start through this call, updates it, and retains static name in a
/// thread-local bounded buffer until report; excess samples are dropped.
pub fn mark(start: *?i64, comptime name: []const u8) void {
    const previous = start.* orelse return;
    const time = now();
    if (count < samples.len) {
        samples[count] = .{ .name = name, .ns = time - previous };
        count += 1;
    }
    start.* = time;
}

/// Writes and clears this thread's collected samples; retains no resources.
/// Caller must invoke after measured startup so output does not affect spans.
pub fn report() void {
    for (samples[0..count]) |sample| stderr.print("scope_detail {s}: {d} ns\n", .{ sample.name, sample.ns });
    count = 0;
}
