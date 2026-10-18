const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;
const num = support.num;

test "Promise: resolved, pending and rejected states" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const done = v8.Promise.from_opaque(env.eval("Promise.resolve(5)").data.handle).?;
            try t.expectEqual(v8.Promise.PromiseState.Fulfilled, done.state());
            try t.expectEqual(@as(?i32, 5), done.result().i32Value(env.context));

            const resolver = v8.Promise.Resolver.init(env.context).?;
            const promise = resolver.getPromise();
            try t.expectEqual(v8.Promise.PromiseState.Pending, promise.state());
            try t.expect(resolver.resolve(env.context, num(env, 8)).?);
            try t.expectEqual(v8.Promise.PromiseState.Fulfilled, promise.state());
            try t.expectEqual(@as(?i32, 8), promise.result().i32Value(env.context));

            const failing = v8.Promise.Resolver.init(env.context).?;
            const failed = failing.getPromise();
            _ = failed.object.value; // keep a handler-free promise from being collected early
            _ = env.eval("0"); // flush
            try t.expect(failing.reject(env.context, env.str("no").name.primitive.value).?);
            try t.expectEqual(v8.Promise.PromiseState.Rejected, failed.state());
        }
    }.run);
}

test "Isolate: microtask checkpoint runs queued jobs" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            env.isolate.setMicrotasksPolicy(.Explicit);
            _ = env.eval("globalThis.ran = false; Promise.resolve().then(() => { ran = true; })");
            try env.expectEval("ran", "false");
            env.isolate.performMicrotasksCheckpoint();
            try env.expectEval("ran", "true");
        }
    }.run);
}
