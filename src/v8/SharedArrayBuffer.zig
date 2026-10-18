const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const SharedArrayBuffer = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn newWithByteLength(isolate: v8.Isolate, byte_length: usize) ?v8.SharedArrayBuffer {
        return v8.SharedArrayBuffer.from_opaque(e.v8__SharedArrayBuffer__New__with_byte_length(isolate.handle, byte_length));
    }

    pub fn newWithBackingStore(isolate: v8.Isolate, backing_store: *const v8.SharedBackingStore) ?v8.SharedArrayBuffer {
        return v8.SharedArrayBuffer.from_opaque(e.v8__SharedArrayBuffer__New__with_backing_store(isolate.handle, backing_store));
    }

    pub fn byteLength(self: v8.SharedArrayBuffer) usize {
        return e.v8__SharedArrayBuffer__ByteLength(self);
    }

    pub fn getBackingStore(self: v8.SharedArrayBuffer) v8.SharedBackingStore {
        const native = e.v8__SharedArrayBuffer__GetBackingStore(self);
        return .{ .a = native.a, .b = native.b };
    }

    pub fn newBackingStoreWithByteLength(isolate: v8.Isolate, byte_length: usize) ?v8.BackingStore {
        return .{ .handle = e.v8__SharedArrayBuffer__NewBackingStore__with_byte_length(isolate.handle, byte_length) orelse return null };
    }

    pub fn newBackingStoreWithData(data: ?*anyopaque, byte_length: usize, deleter: v8.Callbacks.BackingStore_DeleterCallback, deleter_data: ?*anyopaque) ?v8.BackingStore {
        return .{ .handle = e.v8__SharedArrayBuffer__NewBackingStore__with_data(data, byte_length, deleter, deleter_data) orelse return null };
    }
};
