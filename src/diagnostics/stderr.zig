//! Diagnostic output on stderr through libc `write`. `std.debug.print` would pull in
//! `std.Options.debug_io`, a global `std.Io.Threaded`, for a few lines of timing text.
const std = @import("std");

/// Formats into a stack buffer (text beyond it is cut) and writes it; errors are dropped.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buffer: [256]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffer);
    out.print(fmt, args) catch {};
    var rest: []const u8 = out.buffered();
    while (rest.len != 0) {
        const rc = std.c.write(2, rest.ptr, rest.len);
        if (rc < 0) {
            if (std.c.errno(rc) == .INTR) continue;
            return;
        }
        rest = rest[@intCast(rc)..];
    }
}
