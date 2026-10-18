const std = @import("std");
const binding = @import("../generated/binding.zig");
const v8 = @import("../v8.zig");
const support = v8.support;
const V8 = v8.V8;
const e = @import("../generated/externs.gen.zig");

pub const Address = ?*opaque {};

pub const Handle = if (binding.opts.is_direct_handle) Address else *Address;

/// A handle that may be empty. The C ABI uses nullptr for "no handle" in both
/// configurations (see local_to_ptr in binding/support.h). With indirect handles
/// that is an optional pointer; with direct handles `Address` is already nullable,
/// and `?Address` would be an optional of an optional - not a pointer at all.
pub const MaybeHandle = if (binding.opts.is_direct_handle) Handle else ?Handle;

/// How V8 itself spells an empty `Local`/`MaybeLocal`: nullptr normally, but the
/// tagged value 1 (kTaggedNullAddress) with direct handles. Handles returned by the
/// shims are already normalized to null (see binding/support.h); only values that V8
/// hands to a Zig callback, or that a Zig callback returns to V8, use this encoding.
/// Normalized representation of direct-handle Smi zero (raw address zero).
pub const encoded_zero_local: usize = 3;

pub const raw_empty_local: usize = if (binding.opts.is_direct_handle) 1 else 0;

/// Encodes a handle for a callback return value or argument V8 will read directly.
pub fn toRawLocal(h: MaybeHandle) usize {
    const bits = @intFromPtr(h);
    if (binding.opts.is_direct_handle and bits == encoded_zero_local) return 0;
    return if (bits == 0) raw_empty_local else bits;
}

/// Decodes a `Local`/`MaybeLocal` that V8 passed to a callback.
pub fn fromRawLocal(bits: usize) MaybeHandle {
    if (bits == raw_empty_local) return null;
    if (binding.opts.is_direct_handle and bits == 0) return @ptrFromInt(encoded_zero_local);
    return @ptrFromInt(bits);
}

comptime {
    // Local<T> must stay a single pointer-sized value for any of this to hold.
    std.debug.assert(@sizeOf(Handle) == @sizeOf(usize));
}

/// `v8::Local<T>::New`: a new local handle (in the current HandleScope) for any
/// handle-shaped wrapper `other`, e.g. to promote a `Global`'s value.
pub fn localNew(isolate: v8.Isolate, other: anytype) @TypeOf(other) {
    const data = v8.Data.from_opaque(v8.support.rawHandle(other)).?;
    return @TypeOf(other).from_opaque(e.v8__Local__New(isolate.handle, data)).?;
}
