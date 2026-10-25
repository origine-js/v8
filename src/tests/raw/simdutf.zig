//! simdutf wrappers: pure functions, so no isolate is needed.
const std = @import("std");
const v8 = @import("@v8");
const s = v8.simdutf;

test "utf8 <-> utf16 round trip and error positions" {
    const text = "h\xc3\xa9llo \xe2\x82\xac \xf0\x9f\x98\x80";
    try std.testing.expect(s.validateUtf8(text));
    var u16buf: [text.len]u16 = undefined;
    const n = s.convertUtf8ToUtf16(text, &u16buf);
    try std.testing.expectEqual(s.utf16LengthFromUtf8(text), n);
    var back: [text.len]u8 = undefined;
    const m = s.convertUtf16ToUtf8(u16buf[0..n], &back);
    try std.testing.expectEqualStrings(text, back[0..m]);

    const bad = "ab\xffcd";
    const r = s.validateUtf8WithErrors(bad);
    try std.testing.expect(!s.isOk(r));
    try std.testing.expectEqual(@as(usize, 2), r.count);
}

test "latin1 and utf32" {
    const latin = [_]u8{ 'a', 0xe9 };
    var out: [4]u8 = undefined;
    const n = s.convertLatin1ToUtf8(&latin, &out);
    try std.testing.expectEqualStrings("a\xc3\xa9", out[0..n]);
    var l1: [4]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), s.convertUtf8ToLatin1(out[0..n], &l1));
    var u32buf: [4]u32 = undefined;
    try std.testing.expectEqual(@as(usize, 2), s.convertUtf8ToUtf32(out[0..n], &u32buf));
    try std.testing.expectEqual(@as(u32, 0xe9), u32buf[1]);
    try std.testing.expectEqual(@as(usize, 2), s.countUtf8(out[0..n]));
}

test "base64" {
    var enc: [8]u8 = undefined;
    const len = s.base64LengthFromBinary(3, .default);
    try std.testing.expectEqual(@as(usize, 4), len);
    try std.testing.expectEqual(@as(usize, 4), s.binaryToBase64("hi!", enc[0..len], .default));
    try std.testing.expectEqualStrings("aGkh", enc[0..4]);
    var dec: [8]u8 = undefined;
    const r = s.base64ToBinary("aGkh", &dec, .default, .loose);
    try std.testing.expect(s.isOk(r));
    try std.testing.expectEqualStrings("hi!", dec[0..r.count]);
    try std.testing.expect(!s.isOk(s.base64ToBinary("a*kh", &dec, .default, .loose)));
}

test "detect encodings" {
    try std.testing.expect(s.detectEncodings("plain ascii") & s.Encoding.utf8 != 0);
}
