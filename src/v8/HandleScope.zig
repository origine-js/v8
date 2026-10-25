const binding = @import("../generated/binding.zig");
const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;

pub const HandleScope = struct {
    pub const Opaque = [binding.sizes.HandleScope]u8;

    /// V8 placement-constructs pointer-bearing objects here, so it needs pointer alignment.
    inner: Opaque align(@alignOf(usize)),

    const Self = @This();

    pub fn init(self: *Self, isolate: Isolate) void {
        e.v8__HandleScope__CONSTRUCT(&self.inner, isolate.handle);
    }

    pub fn deinit(self: *Self) void {
        e.v8__HandleScope__DESTRUCT(&self.inner);
    }
};
