const v8 = @import("../v8.zig");
const Handle = v8.Handle;

pub const Weak = extern struct {
    handle: Handle,
};
