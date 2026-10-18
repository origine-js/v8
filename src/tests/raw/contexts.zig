const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

test "Isolate: enter, current, data slots" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            try t.expectEqual(env.isolate.handle, v8.Isolate.getCurrent().handle);
            var marker: u32 = 7;
            env.isolate.setData(0, &marker);
            const got: *u32 = @ptrCast(@alignCast(env.isolate.getData(0).?));
            try t.expectEqual(@as(u32, 7), got.*);
            // Local handles are distinct slots, so prove it is the same context via V8.
            env.setGlobal("marker", v8.Number.initInt(env.isolate, 9).numeric.primitive.value);
            const current = env.isolate.getCurrentContext();
            const seen = current.getGlobal().get(current, env.name("marker").primitive.value).?;
            try t.expectEqual(@as(?i32, 9), seen.i32Value(current));
        }
    }.run);
}

test "Isolate: heap statistics and policies" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const stats = env.isolate.getHeapStatistics();
            try t.expect(stats.total_heap_size > 0);
            try t.expect(stats.heap_size_limit >= stats.used_heap_size);

            env.isolate.setMicrotasksPolicy(.Explicit);
            try t.expectEqual(v8.MicrotasksPolicy.Explicit, env.isolate.getMicrotasksPolicy());
            env.isolate.setMicrotasksPolicy(.Auto);
            try t.expectEqual(v8.MicrotasksPolicy.Auto, env.isolate.getMicrotasksPolicy());

            env.isolate.lowMemoryNotification();
            try t.expect(!env.isolate.isExecutionTerminating());
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "Isolate: throwException surfaces in a TryCatch" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();
            _ = env.isolate.throwException(env.str("thrown from zig").name.primitive.value);
            try t.expect(tc_scope.hasCaught());
            const msg = try env.utf8(tc_scope.getException().?);
            defer t.allocator.free(msg);
            try t.expectEqualStrings("thrown from zig", msg);
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "HandleScope: nested scopes release handles" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var i: u32 = 0;
            while (i < 1000) : (i += 1) {
                var h_scope: v8.HandleScope = undefined;
                h_scope.init(env.isolate);
                defer h_scope.deinit();
                _ = env.str("temporary");
            }
        }
    }.run);
}

test "Context: global object and embedder data" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const global = env.context.getGlobal();
            try t.expect(global.set(env.context, env.name("answer").primitive.value, v8.Number.initInt(env.isolate, 42).numeric.primitive.value).?);
            try env.expectEval("answer", "42");

            const other = v8.Context.init(env.isolate, null, null, null);
            try t.expect(other.data.handle != env.context.data.handle);
        }
    }.run);
}
