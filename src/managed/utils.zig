pub fn stringToSlice(
    isolate: v8.Isolate,
    string: v8.String,
    buffer: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
) []const u8 {
    const len = string.lenUtf8(isolate);
    buffer.ensureTotalCapacityPrecise(alloc, len) catch unreachable;
    const buf = buffer.addManyAsSliceAssumeCapacity(len);
    const actual_len = string.writeUtf8(
        isolate,
        buf,
    );
    std.debug.assert(len == actual_len);
    return buf;
}

const std = @import("std");
const v8 = @import("../v8.zig");
