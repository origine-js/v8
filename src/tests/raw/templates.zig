const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;
const num = support.num;

test "ObjectTemplate and Template.set" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const tmpl = v8.ObjectTemplate.initDefault(env.isolate).?;
            tmpl.template.set(env.name("version"), num(env, 3).data, .{ .ReadOnly = true });
            const inst = tmpl.initInstance(env.context).?;
            env.setGlobal("inst", inst.value);
            try env.expectEval("inst.version", "3");
            try env.expectEval("try { inst.version = 9; } catch (e) { if (!(e instanceof TypeError)) throw e; } inst.version", "3");
        }
    }.run);
}

test "Context: embedded global template and embedder data" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const global_tmpl = v8.ObjectTemplate.initDefault(env.isolate).?;
            global_tmpl.template.set(env.name("fromTemplate"), num(env, 11).data, .{});
            var ctx = v8.Context.init(env.isolate, global_tmpl, null, null);
            ctx.enter();
            defer ctx.exit();
            const got = ctx.getGlobal().get(ctx, env.name("fromTemplate").primitive.value).?;
            try t.expectEqual(@as(?i32, 11), got.i32Value(ctx));

            ctx.setEmbedderData(1, num(env, 77).data);
            try t.expectEqual(@as(?i32, 77), (v8.Value{ .data = ctx.getEmbedderData(1) }).i32Value(ctx));
        }
    }.run);
}
