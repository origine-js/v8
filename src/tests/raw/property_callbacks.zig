const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;
const num = support.num;

var accessor_saw_holder_match: bool = false;
var accessor_should_throw: bool = true;

/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn getterAnswer(_: v8.Name, info: *const v8.PropertyCallbackInfo) callconv(.c) void {
    const ctx = info.isolate().getCurrentContext();
    accessor_should_throw = info.shouldThrowOnError();
    const this = info.this();
    const holder = info.holder();
    // Both objects are reachable; for an own accessor they are the same JS object.
    accessor_saw_holder_match = holder.getIdentityHash() == this.getIdentityHash();
    var rv = info.retval();
    const base: i32 = if (info.data()) |d| (v8.Value{ .data = d }).i32Value(ctx) orelse 0 else 0;
    rv.setInt32(base + 1);
}

test "PropertyCallbackInfo: accessor getter sees this, holder, data and return value" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const obj = v8.Object.init(env.isolate);
            try t.expect(obj.setAccessor(env.context, env.name("answer"), getterAnswer, null, num(env, 41), .{}).?);
            env.setGlobal("o", obj.value);
            try env.expectEval("o.answer", "42");
            try t.expect(accessor_saw_holder_match);
        }
    }.run);
}

var setter_received: ?i32 = null;
/// Borrows callback handles through return in the entered context and live
/// HandleScope. Any return value belongs to V8; retains no host pointers or handles.
/// Test observations store only copied scalar values.
fn setterRecord(_: v8.Name, value: v8.Value, info: *const v8.PropertyCallbackInfo) callconv(.c) void {
    setter_received = value.i32Value(info.isolate().getCurrentContext());
}

test "PropertyCallbackInfo: accessor setter receives the assigned value" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            setter_received = null;
            const obj = v8.Object.init(env.isolate);
            try t.expect(obj.setAccessor(env.context, env.name("p"), getterAnswer, setterRecord, null, .{}).?);
            env.setGlobal("o", obj.value);
            _ = env.eval("o.p = 17");
            try t.expectEqual(@as(?i32, 17), setter_received);
            try t.expect(obj.set(env.context, env.name("p").primitive.value, num(env, 0)).?);
            try t.expectEqual(@as(?i32, 0), setter_received);
        }
    }.run);
}
