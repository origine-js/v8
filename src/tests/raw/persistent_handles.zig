const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;
const num = support.num;

test "Global: survives its handle scope" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var persistent: v8.Global = undefined;
            {
                var h_scope: v8.HandleScope = undefined;
                h_scope.init(env.isolate);
                defer h_scope.deinit();
                persistent = .new(env.isolate, num(env, 123).data);
            }
            defer persistent.deinit();
            const again = v8.Value{ .data = persistent.local(env.isolate) };
            try t.expectEqual(@as(?i32, 123), again.i32Value(env.context));
        }
    }.run);
}
