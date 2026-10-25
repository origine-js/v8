//! V8's bundled simdutf. The shims live in binding/binding.cc as `simdutf__*`; their
//! externs are generated into src/generated/externs.gen.zig like the `v8__*` ones.
//! None of these need an isolate, entered context or handle scope, and all are
//! thread-safe: they read their input and write their output buffer during the call
//! and retain nothing afterwards.

/// Mirrors `struct simdutf__result` in binding/binding.cc (generated as
/// `e.support.SimdutfResult`, from typemap.zon). `count` is the number of
/// code units written on success, or the position of the first error otherwise.
pub const Result = e.support.SimdutfResult;

/// `simdutf::error_code` values in `Result.error`.
pub const ErrorCode = enum(c_int) {
    success = 0,
    header_bits = 1,
    too_short = 2,
    too_long = 3,
    overlong = 4,
    too_large = 5,
    surrogate = 6,
    invalid_base64_character = 7,
    base64_input_remainder = 8,
    base64_extra_bits = 9,
    output_buffer_too_small = 10,
    other = 11,
    _,
};

/// Whether `r` reports success. Retains nothing.
pub fn isOk(r: Result) bool {
    return r.@"error" == @intFromEnum(ErrorCode.success);
}

/// `r.error` as an `ErrorCode`. Retains nothing.
pub fn errorCode(r: Result) ErrorCode {
    return @enumFromInt(r.@"error");
}

/// Bits of `detectEncodings`.
pub const Encoding = struct {
    pub const utf8: c_int = 1;
    pub const utf16_le: c_int = 2;
    pub const utf16_be: c_int = 4;
    pub const utf32_le: c_int = 8;
    pub const utf32_be: c_int = 16;
    pub const latin1: c_int = 32;
};

/// `simdutf::base64_options`.
pub const Base64Options = enum(u64) {
    default = 0,
    url = 1,
    default_no_padding = 2,
    url_with_padding = 3,
    default_accept_garbage = 4,
    url_accept_garbage = 5,
    default_or_url = 8,
    default_or_url_accept_garbage = 12,
};

/// `simdutf::last_chunk_handling_options`.
pub const LastChunkHandling = enum(u64) {
    loose = 0,
    strict = 1,
    stop_before_partial = 2,
    only_full_chunks = 3,
};

/// Output buffers are checked with a hard `@panic` (also in release builds): simdutf
/// writes without bounds, so an undersized slice would be a heap overflow.
fn need(ok: bool) void {
    if (!ok) @panic("simdutf: output buffer too small");
}

/// True when `bytes` is strictly valid UTF-8 (no overlongs, surrogates or code points
/// above U+10FFFF). Borrows `bytes` for the call.
pub fn validateUtf8(bytes: []const u8) bool {
    return e.simdutf__validate_utf8(bytes.ptr, bytes.len);
}

/// Like `validateUtf8`; on failure `count` is the byte offset of the first error. Borrows `bytes`.
pub fn validateUtf8WithErrors(bytes: []const u8) Result {
    return e.simdutf__validate_utf8_with_errors(bytes.ptr, bytes.len);
}

/// True when every byte of `bytes` is below 0x80. Borrows `bytes` for the call.
pub fn validateAscii(bytes: []const u8) bool {
    return e.simdutf__validate_ascii(bytes.ptr, bytes.len);
}

/// Like `validateAscii`; on failure `count` is the offset of the first non-ASCII byte.
pub fn validateAsciiWithErrors(bytes: []const u8) Result {
    return e.simdutf__validate_ascii_with_errors(bytes.ptr, bytes.len);
}

/// True when `units` is well-formed UTF-16LE (no lone surrogates). Borrows `units`.
pub fn validateUtf16le(units: []const u16) bool {
    return e.simdutf__validate_utf16le(units.ptr, units.len);
}

/// Like `validateUtf16le`; on failure `count` is the unit offset of the first error.
pub fn validateUtf16leWithErrors(units: []const u16) Result {
    return e.simdutf__validate_utf16le_with_errors(units.ptr, units.len);
}

/// True when `units` is well-formed UTF-16BE. Borrows `units`.
pub fn validateUtf16be(units: []const u16) bool {
    return e.simdutf__validate_utf16be(units.ptr, units.len);
}

/// Like `validateUtf16be`; on failure `count` is the unit offset of the first error.
pub fn validateUtf16beWithErrors(units: []const u16) Result {
    return e.simdutf__validate_utf16be_with_errors(units.ptr, units.len);
}

/// True when every unit of `units` is a Unicode scalar value. Borrows `units`.
pub fn validateUtf32(units: []const u32) bool {
    return e.simdutf__validate_utf32(units.ptr, units.len);
}

/// Like `validateUtf32`; on failure `count` is the unit offset of the first error.
pub fn validateUtf32WithErrors(units: []const u32) Result {
    return e.simdutf__validate_utf32_with_errors(units.ptr, units.len);
}

/// Validates and transcodes UTF-8 to UTF-16LE into `output`, which must hold at least
/// `bytes.len` units (panics otherwise). Returns the units written, or 0 when `bytes` is
/// invalid UTF-8 (`output` is then unspecified). Borrows both slices for the call; they must not overlap.
pub fn convertUtf8ToUtf16(bytes: []const u8, output: []u16) usize {
    need(output.len >= bytes.len);
    return e.simdutf__convert_utf8_to_utf16le(bytes.ptr, bytes.len, output.ptr);
}

/// Like `convertUtf8ToUtf16` but reports the error position: `count` is the units written on
/// success, or the byte offset of the first error.
pub fn convertUtf8ToUtf16WithErrors(bytes: []const u8, output: []u16) Result {
    need(output.len >= bytes.len);
    return e.simdutf__convert_utf8_to_utf16le_with_errors(bytes.ptr, bytes.len, output.ptr);
}

/// Like `convertUtf8ToUtf16` without validating: `bytes` must already be valid UTF-8.
pub fn convertValidUtf8ToUtf16(bytes: []const u8, output: []u16) usize {
    need(output.len >= bytes.len);
    return e.simdutf__convert_valid_utf8_to_utf16le(bytes.ptr, bytes.len, output.ptr);
}

/// UTF-8 to UTF-16BE; same contract as `convertUtf8ToUtf16`.
pub fn convertUtf8ToUtf16be(bytes: []const u8, output: []u16) usize {
    need(output.len >= bytes.len);
    return e.simdutf__convert_utf8_to_utf16be(bytes.ptr, bytes.len, output.ptr);
}

/// UTF-8 to UTF-32; `output` must hold at least `bytes.len` units (panics otherwise).
/// Returns the units written, or 0 on invalid UTF-8.
pub fn convertUtf8ToUtf32(bytes: []const u8, output: []u32) usize {
    need(output.len >= bytes.len);
    return e.simdutf__convert_utf8_to_utf32(bytes.ptr, bytes.len, output.ptr);
}

/// UTF-8 to Latin-1; `output` must hold at least `bytes.len` bytes (panics otherwise).
/// Returns the bytes written, or 0 when `bytes` is invalid UTF-8 or has a code point above U+FF.
pub fn convertUtf8ToLatin1(bytes: []const u8, output: []u8) usize {
    need(output.len >= bytes.len);
    return e.simdutf__convert_utf8_to_latin1(bytes.ptr, bytes.len, output.ptr);
}

/// Like `convertUtf8ToLatin1` but reports the error position in `count`.
pub fn convertUtf8ToLatin1WithErrors(bytes: []const u8, output: []u8) Result {
    need(output.len >= bytes.len);
    return e.simdutf__convert_utf8_to_latin1_with_errors(bytes.ptr, bytes.len, output.ptr);
}

/// Like `convertUtf8ToLatin1` without validating: `bytes` must be valid UTF-8 with only code points <= U+FF.
pub fn convertValidUtf8ToLatin1(bytes: []const u8, output: []u8) usize {
    need(output.len >= bytes.len);
    return e.simdutf__convert_valid_utf8_to_latin1(bytes.ptr, bytes.len, output.ptr);
}

/// Transcodes UTF-16LE to UTF-8 into `output`, which must hold `utf8LengthFromUtf16`
/// bytes (panics otherwise). Returns the bytes written, or 0 on invalid UTF-16 (lone surrogates).
pub fn convertUtf16ToUtf8(units: []const u16, output: []u8) usize {
    need(output.len >= units.len * 3 or output.len >= utf8LengthFromUtf16(units));
    return e.simdutf__convert_utf16le_to_utf8(units.ptr, units.len, output.ptr);
}

/// Like `convertUtf16ToUtf8` but reports the error position (a unit offset) in `count`.
pub fn convertUtf16ToUtf8WithErrors(units: []const u16, output: []u8) Result {
    need(output.len >= units.len * 3 or output.len >= utf8LengthFromUtf16(units));
    return e.simdutf__convert_utf16le_to_utf8_with_errors(units.ptr, units.len, output.ptr);
}

/// Like `convertUtf16ToUtf8` without validating: `units` must be well-formed UTF-16LE.
pub fn convertValidUtf16ToUtf8(units: []const u16, output: []u8) usize {
    need(output.len >= units.len * 3 or output.len >= utf8LengthFromUtf16(units));
    return e.simdutf__convert_valid_utf16le_to_utf8(units.ptr, units.len, output.ptr);
}

/// UTF-16BE to UTF-8; same contract as `convertUtf16ToUtf8` (length via `utf8LengthFromUtf16be`).
pub fn convertUtf16beToUtf8(units: []const u16, output: []u8) usize {
    need(output.len >= units.len * 3 or output.len >= utf8LengthFromUtf16be(units));
    return e.simdutf__convert_utf16be_to_utf8(units.ptr, units.len, output.ptr);
}

/// UTF-32 to UTF-8; `output` must hold `utf8LengthFromUtf32` bytes (panics otherwise).
/// Returns the bytes written, or 0 on invalid input.
pub fn convertUtf32ToUtf8(units: []const u32, output: []u8) usize {
    need(output.len >= units.len * 4 or output.len >= utf8LengthFromUtf32(units));
    return e.simdutf__convert_utf32_to_utf8(units.ptr, units.len, output.ptr);
}

/// Latin-1 to UTF-8; `output` must hold `utf8LengthFromLatin1` bytes (panics otherwise).
pub fn convertLatin1ToUtf8(bytes: []const u8, output: []u8) usize {
    need(output.len >= bytes.len * 2 or output.len >= utf8LengthFromLatin1(bytes));
    return e.simdutf__convert_latin1_to_utf8(bytes.ptr, bytes.len, output.ptr);
}

/// Latin-1 to UTF-16LE; `output` must hold `bytes.len` units (panics otherwise).
pub fn convertLatin1ToUtf16(bytes: []const u8, output: []u16) usize {
    need(output.len >= bytes.len);
    return e.simdutf__convert_latin1_to_utf16le(bytes.ptr, bytes.len, output.ptr);
}

/// UTF-16LE to Latin-1; `output` must hold `units.len` bytes (panics otherwise).
/// Returns the bytes written, or 0 when a unit is above U+FF.
pub fn convertUtf16ToLatin1(units: []const u16, output: []u8) usize {
    need(output.len >= units.len);
    return e.simdutf__convert_utf16le_to_latin1(units.ptr, units.len, output.ptr);
}

/// The UTF-16 units `bytes` decodes to; `bytes` must be valid UTF-8. Borrows `bytes`.
pub fn utf16LengthFromUtf8(bytes: []const u8) usize {
    return e.simdutf__utf16_length_from_utf8(bytes.ptr, bytes.len);
}

/// The UTF-8 bytes `units` (UTF-16LE) encodes to; `units` must be valid UTF-16. Borrows `units`.
pub fn utf8LengthFromUtf16(units: []const u16) usize {
    return e.simdutf__utf8_length_from_utf16le(units.ptr, units.len);
}

/// The UTF-8 bytes `units` (UTF-16BE) encodes to; `units` must be valid UTF-16.
pub fn utf8LengthFromUtf16be(units: []const u16) usize {
    return e.simdutf__utf8_length_from_utf16be(units.ptr, units.len);
}

/// The UTF-8 bytes Latin-1 `bytes` encodes to. Borrows `bytes`.
pub fn utf8LengthFromLatin1(bytes: []const u8) usize {
    return e.simdutf__utf8_length_from_latin1(bytes.ptr, bytes.len);
}

/// The Latin-1 bytes valid UTF-8 `bytes` decodes to. Borrows `bytes`.
pub fn latin1LengthFromUtf8(bytes: []const u8) usize {
    return e.simdutf__latin1_length_from_utf8(bytes.ptr, bytes.len);
}

/// The UTF-32 units valid UTF-8 `bytes` decodes to.
pub fn utf32LengthFromUtf8(bytes: []const u8) usize {
    return e.simdutf__utf32_length_from_utf8(bytes.ptr, bytes.len);
}

/// The UTF-8 bytes valid UTF-32 `units` encodes to.
pub fn utf8LengthFromUtf32(units: []const u32) usize {
    return e.simdutf__utf8_length_from_utf32(units.ptr, units.len);
}

/// The UTF-16 units valid UTF-32 `units` encodes to.
pub fn utf16LengthFromUtf32(units: []const u32) usize {
    return e.simdutf__utf16_length_from_utf32(units.ptr, units.len);
}

/// The UTF-32 units valid UTF-16LE `units` decodes to.
pub fn utf32LengthFromUtf16(units: []const u16) usize {
    return e.simdutf__utf32_length_from_utf16le(units.ptr, units.len);
}

/// The code points in valid UTF-8 `bytes`.
pub fn countUtf8(bytes: []const u8) usize {
    return e.simdutf__count_utf8(bytes.ptr, bytes.len);
}

/// The code points in valid UTF-16LE `units`.
pub fn countUtf16(units: []const u16) usize {
    return e.simdutf__count_utf16le(units.ptr, units.len);
}

/// The code points in valid UTF-16BE `units`.
pub fn countUtf16be(units: []const u16) usize {
    return e.simdutf__count_utf16be(units.ptr, units.len);
}

/// Bitmask of `Encoding` values `bytes` could be. Borrows `bytes`.
pub fn detectEncodings(bytes: []const u8) c_int {
    return e.simdutf__detect_encodings(bytes.ptr, bytes.len);
}

/// Upper bound of the bytes `base64_to_binary` writes for `input`.
pub fn maximalBinaryLengthFromBase64(input: []const u8) usize {
    return e.simdutf__maximal_binary_length_from_base64(input.ptr, input.len);
}

/// Decodes base64 `input` into `output`, which must hold `maximalBinaryLengthFromBase64(input)`
/// bytes (panics otherwise). `count` is the bytes written on success or the error position.
pub fn base64ToBinary(input: []const u8, output: []u8, options: Base64Options, last_chunk: LastChunkHandling) Result {
    need(output.len >= maximalBinaryLengthFromBase64(input));
    return e.simdutf__base64_to_binary(input.ptr, input.len, output.ptr, @intFromEnum(options), @intFromEnum(last_chunk));
}

/// The base64 characters `length` binary bytes encode to under `options`.
pub fn base64LengthFromBinary(length: usize, options: Base64Options) usize {
    return e.simdutf__base64_length_from_binary(length, @intFromEnum(options));
}

/// Encodes `input` as base64 into `output`, which must hold `base64LengthFromBinary(input.len, options)`
/// bytes (panics otherwise). Returns the bytes written.
pub fn binaryToBase64(input: []const u8, output: []u8, options: Base64Options) usize {
    need(output.len >= base64LengthFromBinary(input.len, options));
    return e.simdutf__binary_to_base64(input.ptr, input.len, output.ptr, @intFromEnum(options));
}

const std = @import("std");
const e = @import("../generated/externs.gen.zig");
