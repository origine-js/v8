const std = @import("std");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

/// `v8::StartupData`: a snapshot blob.
pub const StartupData = extern struct {
    data: ?[*]const u8,
    raw_size: c_int,

    const Self = @This();

    pub fn slice(self: Self) []const u8 {
        const d = self.data orelse return &.{};
        return d[0..@intCast(self.raw_size)];
    }

    pub fn canBeRehashed(self: *const Self) bool {
        return e.v8__StartupData__CanBeRehashed(@ptrCast(self));
    }

    pub fn isValid(self: *const Self) bool {
        return e.v8__StartupData__IsValid(@ptrCast(self));
    }

    /// Frees a blob returned by `SnapshotCreator.createBlob`.
    pub fn deinit(self: Self) void {
        e.v8__StartupData__data__DELETE(self.data);
    }
};
