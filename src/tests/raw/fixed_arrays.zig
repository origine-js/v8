const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

test "FixedArray: length and element access (via a PrimitiveArray's backing store)" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const prim = v8.PrimitiveArray.init(env.isolate, 3);
            prim.set(env.isolate, 2, v8.Number.initInt(env.isolate, 31).numeric.primitive);
            const fixed: v8.FixedArray = .{ .data = prim.data };
            try t.expectEqual(@as(c_int, 3), fixed.len());
            const third = v8.Value{ .data = fixed.get(2).? };
            try t.expectEqual(@as(?i32, 31), third.i32Value(env.context));
        }
    }.run);
}
