//! V8's bundled simdutf. The shims live in binding/binding.cc as `simdutf__*`; their
//! externs are generated into src/generated/externs.gen.zig like the `v8__*` ones.
//! None of these need an isolate, entered context or handle scope, and all are
//! thread-safe: they read their input and write their output buffer during the call
//! and retain nothing afterwards.

/// Mirrors `struct simdutf__result` in binding/binding.cc (generated as
/// `e.support.SimdutfResult`, from typemap.zon). `count` is the number of
/// code units written on success, or the position of the first error otherwise.
pub const Result = e.support.SimdutfResult;

/// True when `bytes` is strictly valid UTF-8 (no overlongs, surrogates or code points
/// above U+10FFFF). Borrows `bytes` for the call.
pub fn validateUtf8(bytes: []const u8) bool {
    return e.simdutf__validate_utf8(bytes.ptr, bytes.len);
}

/// True when every byte of `bytes` is below 0x80. Borrows `bytes` for the call.
pub fn validateAscii(bytes: []const u8) bool {
    return e.simdutf__validate_ascii(bytes.ptr, bytes.len);
}

/// Validates and transcodes UTF-8 to UTF-16LE into `output`, which must hold at least
/// `bytes.len` units. Returns the units written, or 0 when `bytes` is invalid UTF-8
/// (`output` is then unspecified). Borrows both slices for the call; they must not overlap.
pub fn convertUtf8ToUtf16(bytes: []const u8, output: []u16) usize {
    std.debug.assert(output.len >= bytes.len);
    return e.simdutf__convert_utf8_to_utf16le(bytes.ptr, bytes.len, output.ptr);
}

/// Like `convertUtf8ToUtf16` without validating: `bytes` must already be valid UTF-8.
pub fn convertValidUtf8ToUtf16(bytes: []const u8, output: []u16) usize {
    std.debug.assert(output.len >= bytes.len);
    return e.simdutf__convert_valid_utf8_to_utf16le(bytes.ptr, bytes.len, output.ptr);
}

/// Transcodes UTF-16LE to UTF-8 into `output`, which must hold `utf8LengthFromUtf16`
/// bytes. Returns the bytes written, or 0 on invalid UTF-16 (lone surrogates).
pub fn convertUtf16ToUtf8(units: []const u16, output: []u8) usize {
    std.debug.assert(output.len >= utf8LengthFromUtf16(units));
    return e.simdutf__convert_utf16le_to_utf8(units.ptr, units.len, output.ptr);
}

/// The UTF-16 units `bytes` decodes to; `bytes` must be valid UTF-8. Borrows `bytes`.
pub fn utf16LengthFromUtf8(bytes: []const u8) usize {
    return e.simdutf__utf16_length_from_utf8(bytes.ptr, bytes.len);
}

/// The UTF-8 bytes `units` encodes to; `units` must be valid UTF-16. Borrows `units`.
pub fn utf8LengthFromUtf16(units: []const u16) usize {
    return e.simdutf__utf8_length_from_utf16le(units.ptr, units.len);
}

const std = @import("std");
const e = @import("../generated/externs.gen.zig");
