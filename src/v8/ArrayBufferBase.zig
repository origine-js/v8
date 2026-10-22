const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

/// Local handle to an ordinary or shared buffer; expires with its handle scope.
pub const ArrayBufferBase = extern struct {
    object: v8.Object,

    /// Borrows an engine-provided buffer handle; returns a local alias in the same scope.
    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    /// Borrows an ordinary, shared, or base buffer; returns an alias in its handle scope.
    pub fn fromBuffer(buffer: anytype) @This() {
        const T = @TypeOf(buffer);
        if (T != v8.ArrayBuffer and T != v8.SharedArrayBuffer and T != @This())
            @compileError("expected ArrayBuffer, SharedArrayBuffer, or ArrayBufferBase");
        return .{ .object = buffer.object };
    }

    /// Borrows the local handle through return; retains no resources.
    pub fn byteLength(self: @This()) usize {
        return e.v8__ArrayBufferBase__ByteLength(self);
    }

    /// Borrows the buffer; storage is valid while it lives and is not detached or resized.
    pub fn data(self: @This()) ?*anyopaque {
        return e.v8__ArrayBufferBase__Data(self);
    }

    /// Returns a caller-owned shared backing-store reference; release it with deinit.
    pub fn getBackingStore(self: @This()) v8.SharedBackingStore {
        const native = e.v8__ArrayBufferBase__GetBackingStore(self);
        return .{ .a = native.a, .b = native.b };
    }
};
