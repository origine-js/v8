const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const Int8Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Int8Array {
        return v8.Int8Array.from_opaque(e.v8__Int8Array__New(buf_ptr, byte_offset, length));
    }
};

pub const Uint8Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Uint8Array {
        return v8.Uint8Array.from_opaque(e.v8__Uint8Array__New(buf_ptr, byte_offset, length));
    }
};

pub const Uint8ClampedArray = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Uint8ClampedArray {
        return v8.Uint8ClampedArray.from_opaque(e.v8__Uint8ClampedArray__New(buf_ptr, byte_offset, length));
    }
};

pub const Int16Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Int16Array {
        return v8.Int16Array.from_opaque(e.v8__Int16Array__New(buf_ptr, byte_offset, length));
    }
};

pub const Uint16Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Uint16Array {
        return v8.Uint16Array.from_opaque(e.v8__Uint16Array__New(buf_ptr, byte_offset, length));
    }
};

pub const Int32Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Int32Array {
        return v8.Int32Array.from_opaque(e.v8__Int32Array__New(buf_ptr, byte_offset, length));
    }
};

pub const Uint32Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Uint32Array {
        return v8.Uint32Array.from_opaque(e.v8__Uint32Array__New(buf_ptr, byte_offset, length));
    }
};

pub const Float16Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Float16Array {
        return v8.Float16Array.from_opaque(e.v8__Float16Array__New(buf_ptr, byte_offset, length));
    }
};

pub const Float32Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Float32Array {
        return v8.Float32Array.from_opaque(e.v8__Float32Array__New(buf_ptr, byte_offset, length));
    }
};

pub const Float64Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.Float64Array {
        return v8.Float64Array.from_opaque(e.v8__Float64Array__New(buf_ptr, byte_offset, length));
    }
};

pub const BigInt64Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.BigInt64Array {
        return v8.BigInt64Array.from_opaque(e.v8__BigInt64Array__New(buf_ptr, byte_offset, length));
    }
};

pub const BigUint64Array = extern struct {
    typedArray: v8.TypedArray,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .typedArray = v8.TypedArray.from_opaque(o) orelse return null };
    }

    pub fn init(buf_ptr: v8.ArrayBuffer, byte_offset: usize, length: usize) ?v8.BigUint64Array {
        return v8.BigUint64Array.from_opaque(e.v8__BigUint64Array__New(buf_ptr, byte_offset, length));
    }
};
