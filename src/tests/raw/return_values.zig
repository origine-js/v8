const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbReturnString(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.set(v8.String.initUtf8(info.isolate(), "str").name.primitive.value);
    // The value just stored can be read back.
    t.expect(rv.get() != null) catch @panic("return value missing");
}
/// Borrows callback locals until return; stores undefined in V8's return slot.
/// Requires the callback's entered context and live HandleScope; retains nothing.
fn cbUndefined(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setUndefined();
}
/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbReturnBool(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setBool(true);
}
/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbReturnInt32(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setInt32(-5);
}
/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbReturnUint32(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setUint32(4000000000);
}
/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbReturnDouble(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setDouble(0.25);
}
/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbReturnNull(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setNull();
}
/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn cbReturnEmptyString(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setEmptyString();
}

test "ReturnValue: every setter" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const cases = [_]struct { v8.FunctionCallback, []const u8, []const u8 }{
                .{ cbReturnString, "typeof f() + f()", "stringstr" },
                .{ cbReturnBool, "f() === true", "true" },
                .{ cbReturnInt32, "f()", "-5" },
                .{ cbReturnUint32, "f()", "4000000000" },
                .{ cbReturnDouble, "f()", "0.25" },
                .{ cbReturnNull, "f() === null", "true" },
                .{ cbUndefined, "f() === undefined", "true" },
                .{ cbReturnEmptyString, "f() === ''", "true" },
            };
            for (cases) |c| {
                const f = v8.Function.init(env.context, c[0], null, 0, .Allow, .HasSideEffect);
                env.setGlobal("f", f.object.value);
                try env.expectEval(c[1], c[2]);
            }
        }
    }.run);
}
