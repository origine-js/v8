const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;
const num = support.num;

var observed_arg_count: c_int = -1;
var observed_construct: bool = false;
var observed_data: ?i32 = null;

/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbSum(info: v8.FunctionCallbackInfo) callconv(.c) void {
    const ctx = info.isolate().getCurrentContext();
    observed_arg_count = info.length();
    var total: i32 = 0;
    var i: c_int = 0;
    while (i < info.length()) : (i += 1) total += info.get_arg(i).i32Value(ctx) orelse 0;
    if (info.data()) |d| observed_data = (v8.Value{ .data = d }).i32Value(ctx);
    var rv = info.retval();
    rv.setInt32(total);
}

test "Function / FunctionCallbackInfo: arguments, data and return value" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            observed_data = null;
            const data = num(env, 1000).data;
            const f = v8.Function.init(env.context, cbSum, data, 2, .Allow, .HasSideEffect);
            env.setGlobal("sum", f.object.value);
            try env.expectEval("sum(1, 2, 3)", "6");
            try t.expectEqual(@as(c_int, 3), observed_arg_count);
            try t.expectEqual(@as(?i32, 1000), observed_data);
            try env.expectEval("sum()", "0");
            try t.expectEqual(@as(c_int, 0), observed_arg_count);
            try env.expectEval("sum.length", "2");
        }
    }.run);
}

test "Function: names and script positions" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const f = v8.Function.init(env.context, cbSum, null, 0, .Allow, .HasSideEffect);
            f.setName(env.str("renamed"));
            const name = try env.utf8(f.getName());
            defer t.allocator.free(name);
            try t.expectEqualStrings("renamed", name);

            const js = v8.Function.from_opaque(env.eval("\n\n(function located() {})").data.handle).?;
            try t.expectEqual(@as(c_int, 2), js.getScriptLineNumber());
            try t.expect(js.getScriptColumnNumber() >= 0);
        }
    }.run);
}

/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbConstruct(info: v8.FunctionCallbackInfo) callconv(.c) void {
    observed_construct = info.isConstructCall();
}

var observed_new_target_is_function: bool = false;
/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbThisAndTarget(info: v8.FunctionCallbackInfo) callconv(.c) void {
    const ctx = info.isolate().getCurrentContext();
    // `this` is a fresh object for `new`, and new.target is the constructor itself.
    _ = info.this().set(ctx, v8.String.initUtf8(info.isolate(), "tag").name.primitive.value, v8.Number.initInt(info.isolate(), 5).numeric.primitive.value);
    observed_new_target_is_function = info.isConstructCall() and !info.newTarget().isNumber();
}

/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbUndefined(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setUndefined();
}

test "FunctionTemplate: builder, instantiation and construct calls" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            observed_construct = false;
            var builder: v8.FunctionTemplate.Builder = .{};
            const tmpl = builder.length(1).constructor_behavior(.Allow).build(env.isolate, cbConstruct, &.{});
            const f = tmpl.getFunction(env.context).?;
            env.setGlobal("Ctor", f.object.value);
            _ = env.eval("new Ctor()");
            try t.expect(observed_construct);
            observed_construct = true;
            _ = env.eval("Ctor()");
            try t.expect(!observed_construct);
            try env.expectEval("Ctor.length", "1");
        }
    }.run);
}

test "FunctionCallbackInfo: this and new.target" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            observed_new_target_is_function = false;
            var builder: v8.FunctionTemplate.Builder = .{};
            const tmpl = builder.build(env.isolate, cbThisAndTarget, &.{});
            env.setGlobal("Tagged", tmpl.getFunction(env.context).?.object.value);
            try env.expectEval("new Tagged().tag", "5");
            try t.expect(observed_new_target_is_function);
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "FunctionTemplate: Throw constructor behaviour rejects new" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();
            var builder: v8.FunctionTemplate.Builder = .{};
            const tmpl = builder.constructor_behavior(.Throw).build(env.isolate, cbUndefined, &.{});
            env.setGlobal("NotCtor", tmpl.getFunction(env.context).?.object.value);
            try t.expect(env.tryEval("new NotCtor()") == null);
            try t.expect(tc_scope.hasCaught());
        }
    }.run);
}
