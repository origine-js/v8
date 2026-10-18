const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbTerminate(info: v8.FunctionCallbackInfo) callconv(.c) void {
    info.isolate().terminateExecution();
}

// Local V8 scopes are released before return; no resources escape.
test "Isolate: terminateExecution stops a runaway script" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();
            const f = v8.Function.init(env.context, cbTerminate, null, 0, .Allow, .HasSideEffect);
            env.setGlobal("stop", f.object.value);

            try t.expect(env.tryEval("stop(); while (true) {}") == null);
            try t.expect(env.isolate.isExecutionTerminating());
            try t.expect(tc_scope.hasTerminated());
            try t.expect(!tc_scope.canContinue());

            env.isolate.cancelTerminateExecution();
            try t.expect(!env.isolate.isExecutionTerminating());
            tc_scope.reset();
            try env.expectEval("1 + 1", "2");
        }
    }.run);
}
