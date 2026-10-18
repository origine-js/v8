const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

test "Array: construct, length and elements" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const empty = v8.Array.init(env.isolate, 3);
            try t.expectEqual(@as(u32, 3), empty.len());

            const items = [_]v8.Value{
                v8.Number.initInt(env.isolate, 1).numeric.primitive.value,
                env.str("two").name.primitive.value,
            };
            const arr = v8.Array.with_elements(env.isolate, &items).?;
            try t.expectEqual(@as(u32, 2), arr.len());
            env.setGlobal("arr", arr.object.value);
            try env.expectEval("arr.join('-')", "1-two");
        }
    }.run);
}

test "PrimitiveArray: set and get" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const arr = v8.PrimitiveArray.init(env.isolate, 2);
            const forty = v8.Number.initInt(env.isolate, 40).numeric.primitive;
            arr.set(env.isolate, 1, forty);
            const got = arr.get(env.isolate, 1);
            try t.expectEqual(@as(?i32, 40), got.value.i32Value(env.context));
        }
    }.run);
}
