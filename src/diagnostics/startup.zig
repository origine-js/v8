//! Inline application startup stage samples; no allocations.
const std = @import("std");
const stderr = @import("stderr.zig");

enabled: bool,
last: i64,
count: usize = 0,
samples: [16]struct { name: []const u8, ns: i64 } = undefined,

/// Reads the process monotonic clock; retains no resources. Clock failure is fatal.
fn now() i64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts) != 0) @panic("startup clock failed");
    return @as(i64, @intCast(ts.sec)) * 1_000_000_000 + @as(i64, @intCast(ts.nsec));
}

/// Reads but does not retain environment storage; returns an owning inline trace.
pub fn init() @This() {
    return .{ .enabled = std.c.getenv("V8_STARTUP_TRACE") != null, .last = now() };
}

/// Borrows self through this call and retains static name until report; allocates nothing.
pub fn mark(self: *@This(), comptime name: []const u8) void {
    if (!self.enabled) return;
    const time = now();
    self.samples[self.count] = .{ .name = name, .ns = time - self.last };
    self.count += 1;
    self.last = time;
}

/// Borrows recorded samples through this call; writes stderr after startup so
/// reporting I/O is excluded from stage times. Retains no resources.
pub fn report(self: *const @This()) void {
    if (!self.enabled) return;
    var total: i64 = 0;
    for (self.samples[0..self.count]) |sample| {
        stderr.print("startup {s}: {d} ns\n", .{ sample.name, sample.ns });
        total += sample.ns;
    }
    stderr.print("startup total: {d} ns\n", .{total});
}
