const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const BackingStore = extern struct {
    pub const Opaque = opaque {};
    handle: *Opaque,

    pub fn isResizableByUserJavaScript(self: v8.BackingStore) bool {
        return e.v8__BackingStore__IsResizableByUserJavaScript(self);
    }

    pub fn data(self: v8.BackingStore) ?*anyopaque {
        return e.v8__BackingStore__Data(self);
    }

    pub fn byteLength(self: v8.BackingStore) usize {
        return e.v8__BackingStore__ByteLength(self);
    }

    pub fn isShared(self: v8.BackingStore) bool {
        return e.v8__BackingStore__IsShared(self);
    }

    pub fn deinit(self: v8.BackingStore) void {
        e.v8__BackingStore__DELETE(self.handle);
    }
};
