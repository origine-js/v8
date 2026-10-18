/// Native context configuration. `.limited = 0` is equivalent to `.none`;
/// getters canonicalize zero to `.none`. Values retain no resources.
pub const StackTraceLimit = union(enum) {
    unlimited,
    limited: u31,
    none,

    /// Converts a value to the native representation; retains no resources.
    pub fn toNative(self: StackTraceLimit) c_int {
        return switch (self) {
            .unlimited => -1,
            .limited => |frames| @intCast(frames),
            .none => 0,
        };
    }

    /// Converts a valid native limit (-1 or nonnegative); retains no resources.
    pub fn fromNative(value: c_int) StackTraceLimit {
        return switch (value) {
            -1 => .unlimited,
            0 => .none,
            else => .{ .limited = @intCast(value) },
        };
    }
};
