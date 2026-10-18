const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

/// Borrows env/source/name through compilation and execution; V8 copies strings.
/// Returns a local value valid until the fixture HandleScope closes, or null on
/// JavaScript failure (the caller's TryCatch holds the error). Retains no host bytes.
fn evalNamed(env: *Env, src: []const u8, name: []const u8) ?v8.Value {
    const origin = v8.ScriptOrigin.initDefault(env.str(name).name.primitive.value);
    const script = v8.Script.compile(env.context, env.str(src), origin) orelse return null;
    return script.run(env.context);
}

// Local V8 scopes are released before return; no resources escape.
test "Script: compile and run, syntax errors, runtime errors" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();

            const script = v8.Script.compile(env.context, env.str("6 * 7"), null).?;
            try t.expectEqual(@as(?i32, 42), script.run(env.context).?.i32Value(env.context));
            try t.expect(!tc_scope.hasCaught());

            try t.expect(v8.Script.compile(env.context, env.str("let = ;"), null) == null);
            try t.expect(tc_scope.hasCaught());
            tc_scope.reset();
            try t.expect(!tc_scope.hasCaught());

            const failing = v8.Script.compile(env.context, env.str("null.x"), null).?;
            try t.expect(failing.run(env.context) == null);
            try t.expect(tc_scope.hasCaught());
        }
    }.run);
}

test "String/Script/Object/Promise: concat, script ids, callability, markAsHandled" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            const joined = v8.String.concat(env.isolate, env.str("foo"), env.str("bar")).?;
            try t.expectEqual(@as(c_int, 6), joined.len());

            const script = v8.Script.compile(env.context, env.str("1"), null).?;
            const other = v8.Script.compile(env.context, env.str("2"), null).?;
            try t.expect(script.scriptId() != other.scriptId());
            try t.expectEqual(script.scriptId(), script.getUnboundScript().?.scriptId());

            const fn_obj = v8.Object.from_opaque(env.eval("(function () {})").data.handle).?;
            const arrow = v8.Object.from_opaque(env.eval("(() => 1)").data.handle).?;
            const plain = v8.Object.from_opaque(env.eval("({})").data.handle).?;
            try t.expect(fn_obj.isCallable() and fn_obj.isConstructor());
            try t.expect(arrow.isCallable() and !arrow.isConstructor());
            try t.expect(!plain.isCallable() and !plain.isConstructor());

            const rejected = v8.Promise.from_opaque(env.eval("Promise.reject(1)").data.handle).?;
            try t.expect(!rejected.hasHandler());
            rejected.markAsHandled();
            try t.expect(rejected.hasHandler());
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "TryCatch: exception, flags and reset" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();

            try t.expect(!tc_scope.hasCaught());
            try t.expect(!tc_scope.isVerbose());
            tc_scope.setVerbose(false);
            tc_scope.setCaptureMessage(true);

            try t.expect(env.tryEval("throw new RangeError('out of range')") == null);
            try t.expect(tc_scope.hasCaught());
            try t.expect(tc_scope.canContinue());
            try t.expect(!tc_scope.hasTerminated());

            const text = try env.utf8(tc_scope.getException().?);
            defer t.allocator.free(text);
            try t.expectEqualStrings("RangeError: out of range", text);

            tc_scope.reset();
            try t.expect(!tc_scope.hasCaught());
            try t.expect(tc_scope.getException() == null);
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "TryCatch: reThrow hands the exception to the outer catcher" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();
            {
                var inner_tc_scope: v8.TryCatch = undefined;
                inner_tc_scope.init(env.isolate);
                defer inner_tc_scope.deinit();
                try t.expect(env.tryEval("throw 'inner'") == null);
                try t.expect(inner_tc_scope.hasCaught());
                _ = inner_tc_scope.reThrow();
            }
            try t.expect(tc_scope.hasCaught());
            const text = try env.utf8(tc_scope.getException().?);
            defer t.allocator.free(text);
            try t.expectEqualStrings("inner", text);
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "Message: location and text of an uncaught error" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();

            try t.expect(evalNamed(env, "var a = 1;\nvar b = oops + a;", "messages.js") == null);
            const msg = tc_scope.getMessage().?;

            const text = try env.utf8(msg.get().name.primitive.value);
            defer t.allocator.free(text);
            try t.expectEqualStrings("Uncaught ReferenceError: oops is not defined", text);

            const line = try env.utf8(msg.getSourceLine(env.context).?.name.primitive.value);
            defer t.allocator.free(line);
            try t.expectEqualStrings("var b = oops + a;", line);

            const resource = try env.utf8(msg.getScriptResourceName());
            defer t.allocator.free(resource);
            try t.expectEqualStrings("messages.js", resource);

            try t.expectEqual(@as(?c_uint, 2), msg.getLineNumber(env.context));
            try t.expectEqual(@as(?c_uint, 8), msg.getStartColumn());
            // V8 reports a one-character range for a ReferenceError.
            try t.expect(msg.getEndColumn().? > msg.getStartColumn().?);
            try t.expect(msg.getEndPosition() > msg.getStartPosition());
            try t.expectEqual(@as(i32, -1), msg.getWasmFunctionIndex());
            _ = msg.getErrorLevel();
            try t.expect(!msg.isSharedCrossOrigin());
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "ScriptOrigin: resource name and offsets reach error locations" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();

            const origin = v8.ScriptOrigin.init(
                env.str("shifted.js").name.primitive.value,
                10, // line offset
                0,
                true, // shared cross origin
                -1,
                null,
                false,
                false,
                false,
                null,
            );
            const script = v8.Script.compile(env.context, env.str("throw new Error('x')"), origin).?;
            try t.expect(script.run(env.context) == null);
            const msg = tc_scope.getMessage().?;
            try t.expectEqual(@as(?c_uint, 11), msg.getLineNumber(env.context));
            try t.expect(msg.isSharedCrossOrigin());
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "StackTrace and StackFrame: captured from an uncaught error" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            env.isolate.setCaptureStackTraceForUncaughtExceptions(true, 10);
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();

            const src =
                \\function inner() { throw new Error('deep'); }
                \\function outer() { inner(); }
                \\outer();
            ;
            try t.expect(evalNamed(env, src, "stack.js") == null);
            const trace = tc_scope.getMessage().?.getStackTrace().?;
            try t.expect(trace.getFrameCount() >= 3);

            const top = trace.getFrame(env.isolate, 0);
            try t.expectEqual(@as(c_int, 1), top.getLineNumber());
            try t.expect(top.getColumn() > 0);
            try t.expect(top.getScriptId() > 0);
            try t.expect(top.isUserJavascript());
            try t.expect(!top.isEval());
            try t.expect(!top.isConstructor());
            try t.expect(!top.isWasm());

            const fn_name = try env.utf8(top.getFunctionName().?.name.primitive.value);
            defer t.allocator.free(fn_name);
            try t.expectEqualStrings("inner", fn_name);

            const script_name = try env.utf8(top.getScriptName().?.name.primitive.value);
            defer t.allocator.free(script_name);
            try t.expectEqualStrings("stack.js", script_name);

            const url = top.getScriptNameOrSourceUrl().?;
            try t.expect(url.len() > 0);

            const caller = trace.getFrame(env.isolate, 1);
            const caller_name = try env.utf8(caller.getFunctionName().?.name.primitive.value);
            defer t.allocator.free(caller_name);
            try t.expectEqualStrings("outer", caller_name);
        }
    }.run);
}

var current_trace_frames: c_int = 0;
var current_trace_name_len: c_int = -1;

/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbCaptureStack(info: v8.FunctionCallbackInfo) callconv(.c) void {
    const trace = v8.StackTrace.getCurrentStackTrace(info.isolate(), 8);
    current_trace_frames = trace.getFrameCount();
    if (v8.StackTrace.getCurrentScriptNameOrSourceUrl(info.isolate())) |name| current_trace_name_len = name.len();
}

test "StackTrace: current stack from inside a native callback" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            current_trace_frames = 0;
            current_trace_name_len = -1;
            const f = v8.Function.init(env.context, cbCaptureStack, null, 0, .Allow, .HasSideEffect);
            env.setGlobal("capture", f.object.value);
            _ = evalNamed(env, "function viaJs() { capture(); }\nviaJs();", "current.js").?;
            try t.expect(current_trace_frames >= 2);
            try t.expectEqual(@as(c_int, "current.js".len), current_trace_name_len);
        }
    }.run);
}
