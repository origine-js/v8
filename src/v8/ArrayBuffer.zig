const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Object = v8.Object;

pub const ArrayBuffer = extern struct {
    object: Object,

    pub const Allocator = extern struct {
        pub const Opaque = opaque {};

        handle: *Opaque,

        pub fn initDefault() @This() {
            return .{
                .handle = e.v8__ArrayBuffer__Allocator__NewDefaultAllocator().?,
            };
        }

        pub fn deinit(self: @This()) void {
            e.v8__ArrayBuffer__Allocator__DELETE(self.handle);
        }

        pub fn newZigAllocator(handle: ?*anyopaque, vtable: *const v8.ZigAllocatorTable) ?v8.ArrayBuffer.Allocator {
            return .{ .handle = e.v8__ArrayBuffer__Allocator__NewZigAllocator(handle, vtable) orelse return null };
        }
    };

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn newBackingStoreWithByteLength(isolate: v8.Isolate, byte_length: usize) ?v8.BackingStore {
        return .{ .handle = e.v8__ArrayBuffer__NewBackingStore__with_byte_length(isolate.handle, byte_length) orelse return null };
    }

    pub fn newBackingStoreWithData(data_arg: ?*anyopaque, byte_length: usize, deleter: v8.Callbacks.BackingStore_DeleterCallback, deleter_data: ?*anyopaque) ?v8.BackingStore {
        return .{ .handle = e.v8__ArrayBuffer__NewBackingStore__with_data(data_arg, byte_length, deleter, deleter_data) orelse return null };
    }

    pub fn getBackingStore(self: v8.ArrayBuffer) v8.SharedBackingStore {
        const native = e.v8__ArrayBuffer__GetBackingStore(self);
        return .{ .a = native.a, .b = native.b };
    }

    pub fn data(self: v8.ArrayBuffer) ?*anyopaque {
        return e.v8__ArrayBuffer__Data(self);
    }

    pub fn detach(self: v8.ArrayBuffer, key: ?v8.Value) ?bool {
        return e.v8__ArrayBuffer__Detach(self, if (key) |v| v8.support.rawHandle(v) else null).as_optional();
    }

    pub fn isDetachable(self: v8.ArrayBuffer) bool {
        return e.v8__ArrayBuffer__IsDetachable(self);
    }

    pub fn wasDetached(self: v8.ArrayBuffer) bool {
        return e.v8__ArrayBuffer__WasDetached(self);
    }

    pub fn setDetachKey(self: v8.ArrayBuffer, key: ?v8.Value) void {
        e.v8__ArrayBuffer__SetDetachKey(self, if (key) |v| v8.support.rawHandle(v) else null);
    }

    pub fn newWithByteLength(isolate: v8.Isolate, byte_length: usize) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.from_opaque(e.v8__ArrayBuffer__New__with_byte_length(isolate.handle, byte_length));
    }

    pub fn newWithBackingStore(isolate: v8.Isolate, backing_store: *const v8.SharedBackingStore) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.from_opaque(e.v8__ArrayBuffer__New__with_backing_store(isolate.handle, backing_store));
    }

    pub fn byteLength(self: v8.ArrayBuffer) usize {
        return e.v8__ArrayBuffer__ByteLength(self);
    }
};
