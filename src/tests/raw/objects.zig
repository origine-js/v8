const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;
const num = support.num;

test "Object: get, set, index access" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const obj = v8.Object.init(env.isolate);
            const key = env.name("k").primitive.value;
            try t.expect(obj.set(env.context, key, num(env, 5)).?);
            try t.expectEqual(@as(?i32, 5), obj.get(env.context, key).?.i32Value(env.context));

            try t.expect(obj.setIndex(env.context, 3, num(env, 9)).?);
            try t.expectEqual(@as(?i32, 9), obj.getIndex(env.context, 3).?.i32Value(env.context));

            env.setGlobal("o", obj.value);
            try env.expectEval("JSON.stringify(o)", "{\"3\":9,\"k\":5}");
        }
    }.run);
}

test "Object: initWithProperties takes an explicit prototype" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const names = [_]v8.Name{ env.name("a"), env.name("b") };
            const values = [_]v8.Value{ num(env, 1), env.str("two").name.primitive.value };

            // JS null: an object with no prototype at all.
            const bare = v8.Object.initWithProperties(env.isolate, v8.Primitive.initNull(env.isolate).value, &names, &values);
            env.setGlobal("bare", bare.value);
            try env.expectEval("bare.a + ':' + bare.b", "1:two");
            try env.expectEval("Object.getPrototypeOf(bare) === null", "true");

            // An object prototype is inherited.
            const proto = env.eval("({ inherited: 'yes' })");
            const child = v8.Object.initWithProperties(env.isolate, proto, &names, &values);
            env.setGlobal("child", child.value);
            try env.expectEval("child.inherited + child.a", "yes1");
        }
    }.run);
}

test "Object: prototype, constructor name, identity hash, creation context" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const map = v8.Object.from_opaque(env.eval("new Map()").data.handle).?;
            const ctor = map.getConstructorName();
            const name = try env.utf8(ctor.name.primitive.value);
            defer t.allocator.free(name);
            try t.expectEqualStrings("Map", name);

            const proto = map.getPrototype().?;
            env.setGlobal("proto", proto);
            try env.expectEval("proto === Map.prototype", "true");

            const plain = v8.Object.init(env.isolate);
            try t.expect(!plain.isApiWrapper());
            try t.expect(plain.getIdentityHash() == plain.getIdentityHash());
            try t.expect(plain.getCreationContext() != null);

            try t.expect(plain.setPrototype(env.context, proto).?);
        }
    }.run);
}

test "Object: createDataProperty and defineOwnProperty honour attributes" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const obj = v8.Object.init(env.isolate);
            try t.expect(obj.createDataProperty(env.context, env.name("x"), num(env, 1)).?);
            try t.expect(obj.defineOwnProperty(env.context, env.name("fixed"), num(env, 2), .{ .ReadOnly = true, .DontEnum = true }).?);
            env.setGlobal("o", obj.value);
            try env.expectEval("Object.keys(o).join()", "x");
            try env.expectEval("try { o.fixed = 99; } catch (e) { if (!(e instanceof TypeError)) throw e; } o.fixed", "2");
        }
    }.run);
}

test "PropertyDescriptor: value and accessor descriptors" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            const obj = v8.Object.init(env.isolate);
            env.setGlobal("o", obj.value);

            var data = v8.PropertyDescriptor.initValue(num(env, 7), false);
            defer data.deinit();
            try t.expect(obj.defineProperty(env.context, env.name("d"), &data).?);
            try env.expectEval("o.d", "7");
            try env.expectEval("Object.getOwnPropertyDescriptor(o, 'd').writable", "false");

            const getter = env.eval("(function () { return 'got'; })");
            const setter = env.eval("(function (v) { this.stored = v; })");
            var accessor = v8.PropertyDescriptor.initGetSet(getter, setter);
            defer accessor.deinit();
            try t.expect(obj.defineProperty(env.context, env.name("a"), &accessor).?);
            try env.expectEval("(o.a = 'x', o.a + '/' + o.stored)", "got/x");
        }
    }.run);
}
