const binding = @import("../binding.zig");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;

pub const HandleScope = struct {
    pub const Opaque = [binding.sizes.HandleScope]u8;

    inner: Opaque,

    const Self = @This();

    pub fn init(self: *Self, isolate: Isolate) void {
        e.v8__HandleScope__CONSTRUCT(&self.inner, isolate.handle);
    }

    pub fn deinit(self: *Self) void {
        e.v8__HandleScope__DESTRUCT(&self.inner);
    }
};
