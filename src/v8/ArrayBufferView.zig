const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const ArrayBufferView = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn buffer(self: v8.ArrayBufferView) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.from_opaque(e.v8__ArrayBufferView__Buffer(self));
    }

    pub fn bufferData(self: v8.ArrayBufferView) ?*const anyopaque {
        return e.v8__ArrayBufferView__Buffer__Data(self);
    }

    pub fn byteLength(self: v8.ArrayBufferView) usize {
        return e.v8__ArrayBufferView__ByteLength(self);
    }

    pub fn byteOffset(self: v8.ArrayBufferView) usize {
        return e.v8__ArrayBufferView__ByteOffset(self);
    }

    pub fn hasBuffer(self: v8.ArrayBufferView) bool {
        return e.v8__ArrayBufferView__HasBuffer(self);
    }

    pub fn copyContents(self: v8.ArrayBufferView, dest: ?*anyopaque, byte_length: c_int) usize {
        return e.v8__ArrayBufferView__CopyContents(self, dest, byte_length);
    }

    pub fn getContents(self: v8.ArrayBufferView, rstorage: e.support.MemorySpan) e.support.MemorySpan {
        return e.v8__ArrayBufferView__GetContents(self, rstorage);
    }
};
