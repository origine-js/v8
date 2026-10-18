const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const MaybeHandle = v8.MaybeHandle;
const Isolate = v8.Isolate;
const Context = v8.Context;
const String = v8.String;
const Value = v8.Value;
const Numeric = v8.Numeric;

pub const BigInt = extern struct {
    numeric: Numeric,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .numeric = Numeric.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, v: i64) @This() {
        return from_opaque(e.v8__BigInt__New(isolate.handle, v)).?;
    }

    pub fn initFromUnsigned(isolate: Isolate, v: u64) @This() {
        return from_opaque(e.v8__BigInt__NewFromUnsigned(isolate.handle, v)).?;
    }

    /// Null if V8 throws (e.g. more than the maximum number of words).
    pub fn initFromWords(context: Context, negative: bool, words: []const u64) ?@This() {
        return from_opaque(e.v8__BigInt__NewFromWords(
            context,
            @intFromBool(negative),
            @intCast(words.len),
            @ptrCast(words.ptr),
        ));
    }

    /// Returns the value modulo 2^64; `lossless` (if given) reports exactness.
    pub fn uint64Value(self: @This(), lossless: ?*bool) u64 {
        return e.v8__BigInt__Uint64Value(self, lossless);
    }

    pub fn int64Value(self: @This(), lossless: ?*bool) i64 {
        return e.v8__BigInt__Int64Value(self, lossless);
    }

    pub fn wordCount(self: @This()) usize {
        return @intCast(e.v8__BigInt__WordCount(self));
    }

    /// Writes up to `words.len` words; returns the sign (true = negative) and the
    /// total number of words the value needs.
    pub fn toWordsArray(self: @This(), words: []u64) struct { negative: bool, word_count: usize } {
        var sign: c_int = 0;
        var count: c_int = @intCast(words.len);
        e.v8__BigInt__ToWordsArray(self, &sign, &count, @ptrCast(words.ptr));
        return .{ .negative = sign != 0, .word_count = @intCast(count) };
    }
};
