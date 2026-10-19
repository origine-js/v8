const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

test "String: encodings and lengths" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const utf8 = v8.String.initUtf8(env.isolate, "héllo 🍏");
            try t.expectEqual(@as(c_int, 8), utf8.len()); // 🍏 is a surrogate pair
            try t.expectEqual(@as(usize, 11), utf8.lenUtf8(env.isolate));

            const one = v8.String.initOneByte(env.isolate, "abc");
            try t.expectEqual(@as(c_int, 3), one.len());

            const wide = v8.String.initTwoByte(env.isolate, &[_]u16{ 'h', 'i', 0xD83C, 0xDF4F });
            try t.expectEqual(@as(c_int, 4), wide.len()); // two code units for the emoji

            const static = v8.String.initOneByteStatic(env.isolate, "static");
            try t.expectEqual(@as(c_int, 6), static.len());

            var buf: [11]u8 = undefined;
            try t.expectEqual(@as(usize, 11), utf8.writeUtf8(env.isolate, &buf));
            try t.expectEqualStrings("héllo 🍏", &buf);

            // Lone surrogates are written as U+FFFD (EF BF BD), not as WTF-8.
            const lone = v8.String.initTwoByte(env.isolate, &[_]u16{ 'a', 0xD800, 'b' });
            var lone_buf: [5]u8 = undefined;
            try t.expectEqual(@as(usize, 5), lone.writeUtf8(env.isolate, &lone_buf));
            try t.expectEqualSlices(u8, &.{ 'a', 0xEF, 0xBF, 0xBD, 'b' }, &lone_buf);
        }
    }.run);
}

test "Value: conversions" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const forty_two = env.eval("40 + 2");
            try t.expect(forty_two.isNumber());
            try t.expectEqual(@as(?u32, 42), forty_two.u32Value(env.context));
            try t.expectEqual(@as(?i32, 42), forty_two.i32Value(env.context));
            try t.expectEqual(@as(?i32, -1), env.eval("-1").i32Value(env.context));
            try t.expect(!env.eval("'text'").isNumber());
            try env.expectEval("[1, [2, 3]]", "1,2,3");
        }
    }.run);
}

test "Number, Numeric and Primitive" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            try t.expectEqual(@as(f64, 1.5), v8.Number.init(env.isolate, 1.5).Value());
            try t.expectEqual(@as(f64, -7), v8.Number.initInt(env.isolate, -7).Value());
            try t.expectEqual(@as(f64, 4294967295), v8.Number.initUInt(env.isolate, 4294967295).Value());

            const n = v8.Number.init(env.isolate, 3);
            try t.expect(n.numeric.primitive.value.isNumber());
        }
    }.run);
}

test "Primitive: null and undefined" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            env.setGlobal("n", v8.Primitive.initNull(env.isolate).value);
            env.setGlobal("u", v8.Primitive.initUndefined(env.isolate).value);
            try env.expectEval("n === null && u === undefined", "true");
        }
    }.run);
}

test "Name: strings are names" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const n = env.name("key");
            const back = try env.utf8(n.primitive.value);
            defer t.allocator.free(back);
            try t.expectEqualStrings("key", back);
        }
    }.run);
}

test "External: round-trips a native pointer" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            var payload: u64 = 0xdead_beef;
            const ext = v8.External.init(env.isolate, &payload);
            const got: *u64 = @ptrCast(@alignCast(ext.pointer().?));
            try t.expectEqual(@as(u64, 0xdead_beef), got.*);
        }
    }.run);
}

test "Data: handles compare by identity" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const a = env.eval("({})");
            const same = v8.Data.from_opaque(a.data.handle).?;
            try t.expectEqual(a.data.handle, same.handle);
        }
    }.run);
}
