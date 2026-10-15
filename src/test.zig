//! Behavioural tests for the wrappers in v8.zig, one group per wrapper type.
//!
//! V8 can only be initialised once per process and never torn down, so the
//! platform is shared; every test gets its own isolate, handle scope and context.

const std = @import("std");
const t = std.testing;
const v8 = @import("v8.zig");
const binding = @import("binding.zig");

var platform: v8.Platform = undefined;
var v8_ready = false;

pub fn ensureV8() void {
    if (v8_ready) return;
    platform = .initDefault(0, true);
    v8.V8.initializePlatform(platform);
    v8.V8.initialize();
    v8_ready = true;
}

const Env = struct {
    allocator: v8.ArrayBuffer.Allocator,
    params: v8.Isolate.CreateParams,
    isolate: v8.Isolate,
    hscope: v8.HandleScope,
    context: v8.Context,

    fn start(self: *Env) void {
        ensureV8();
        self.params = .init();
        self.allocator = .initDefault();
        self.params.array_buffer_allocator = self.allocator;
        self.isolate = .init(&self.params);
        self.isolate.enter();
        self.hscope.init(self.isolate);
        self.context = .init(self.isolate, null, null, null);
        self.context.enter();
    }

    fn stop(self: *Env) void {
        self.context.exit();
        self.hscope.deinit();
        self.isolate.exit();
        self.isolate.deinit();
        self.allocator.deinit();
    }

    fn str(self: *Env, s: []const u8) v8.String {
        return .initUtf8(self.isolate, s);
    }

    fn name(self: *Env, s: []const u8) v8.Name {
        return self.str(s).name;
    }

    /// Compiles and runs `src`; null if it throws.
    fn tryEval(self: *Env, src: []const u8) ?v8.Value {
        const script = v8.Script.compile(self.context, self.str(src), null) orelse return null;
        return script.run(self.context);
    }

    fn eval(self: *Env, src: []const u8) v8.Value {
        return self.tryEval(src) orelse @panic("script threw");
    }

    /// `String(value)` as UTF-8, owned by the testing alloc.
    fn utf8(self: *Env, value: v8.Value) ![]u8 {
        const s = value.toString(self.context).?;
        const buf = try t.allocator.alloc(u8, s.lenUtf8(self.isolate));
        _ = s.writeUtf8(self.isolate, buf);
        return buf;
    }

    fn expectEval(self: *Env, src: []const u8, expected: []const u8) !void {
        const got = try self.utf8(self.eval(src));
        defer t.allocator.free(got);
        try t.expectEqualStrings(expected, got);
    }

    fn setGlobal(self: *Env, key: []const u8, value: v8.Value) void {
        _ = self.context.getGlobal().set(self.context, self.name(key).primitive.value, value);
    }
};

fn withEnv(comptime body: fn (*Env) anyerror!void) !void {
    var env: Env = undefined;
    env.start();
    defer env.stop();
    try body(&env);
}

// ------------------------------------------------------------------ V8 / Platform

test "Intrinsics: frozen identity, rejected tampering, realm ownership and GC" {
    try withEnv(struct {
        /// Borrows env and its entered context/live HandleScope through return;
        /// all created local handles expire with that scope; retains no resources.
        fn run(env: *Env) !void {
            const push = v8.Intrinsics.get(env.context, "ArrayPrototypePush").?;
            try t.expect(push.object.value.strictEquals(env.eval("Array.prototype.push")));
            const methods = .{
                .{ "ObjectFreeze", "Object.freeze" },
                .{ "ReflectApply", "Reflect.apply" },
                .{ "MapPrototypeGet", "Map.prototype.get" },
                .{ "ArrayPrototypeValues", "Array.prototype[Symbol.iterator]" },
            };
            inline for (methods) |method| {
                try t.expect(v8.Intrinsics.get(env.context, method[0]).?.object.value.strictEquals(env.eval(method[1])));
            }
            const other = v8.Context.init(env.isolate, null, null, null);
            try t.expect(!push.object.value.strictEquals(v8.Intrinsics.get(other, "ArrayPrototypePush").?.object.value));

            try t.expect(env.eval(
                \\!Reflect.defineProperty(Array.prototype, 'push', {
                \\  get() { throw 'poisoned push getter'; }, configurable: true
                \\}) && !Reflect.set(Function.prototype, 'call', () => {}) &&
                \\!Reflect.set(globalThis, 'Array', () => {})
            ).isTrue());
            env.isolate.lowMemoryNotification();
            const recovered = v8.Intrinsics.get(env.context, "ArrayPrototypePush").?;
            try t.expect(push.object.value.strictEquals(recovered.object.value));
            const all = v8.Intrinsics.getAll(env.context).?;
            try t.expect(all.getPrototype().?.isNull());
            env.setGlobal("allIntrinsics", all.value);
            try t.expect(env.eval("Object.isFrozen(allIntrinsics)").isTrue());
            try t.expect(env.eval("!Object.hasOwn(allIntrinsics, 'ReturnReceiver') && !Object.hasOwn(allIntrinsics, 'Call_ReceiverIsAny')").isTrue());
            const keys = all.getOwnPropertyNames(env.context, 0, 0).?;
            try t.expect(keys.len() > 0);
            var index: u32 = 0;
            while (index < keys.len()) : (index += 1) {
                const key = keys.object.getIndex(env.context, index).?;
                const name = try env.utf8(key);
                defer t.allocator.free(name);
                try t.expect(all.get(env.context, key).?.strictEquals(v8.Intrinsics.get(env.context, name).?.object.value));
            }
            const array = v8.Array.init(env.isolate, 0);
            const result = recovered.call(env.context, array.object.value, &.{env.eval("42")}).?;
            try t.expectEqual(@as(i32, 1), result.i32Value(env.context).?);
            try t.expectEqual(@as(u32, 1), array.len());
            try t.expectEqual(@as(i32, 42), array.object.getIndex(env.context, 0).?.i32Value(env.context).?);
            try t.expect(v8.Intrinsics.get(env.context, "NoSuchBuiltin") == null);
            try t.expect(v8.Intrinsics.get(env.context, "ArrayPrototypePush\x00suffix") == null);
            try t.expect(v8.Intrinsics.get(env.context, "") == null);
            try t.expect(v8.Intrinsics.get(env.context, "Call_ReceiverIsAny") == null);
            // Several public symbol methods have distinct identities but share
            // ReturnReceiver's code. A builtin name cannot disambiguate them.
            try t.expect(v8.Intrinsics.get(env.context, "ReturnReceiver") == null);
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "Intrinsics: frozen graph and bindings survive a custom context snapshot" {
    ensureV8();
    const aba = v8.ArrayBuffer.Allocator.initDefault();
    defer aba.deinit();
    var params = v8.Isolate.CreateParams.init();
    params.array_buffer_allocator = aba;
    const blob = make: {
        var creator: v8.SnapshotCreator = undefined;
        creator.init(&params);
        defer creator.deinit();
        const isolate = creator.getIsolate().?;
        {
            var h_scope: v8.HandleScope = undefined;
            h_scope.init(isolate);
            defer h_scope.deinit();
            const context = v8.Context.init(isolate, null, null, null);
            context.enter();
            defer context.exit();
            const script = v8.Script.compile(context, v8.String.initUtf8(isolate, "Object.isFrozen(Array.prototype) && !Reflect.set(globalThis, 'Array', () => {})"), null).?;
            try t.expect(script.run(context).?.isTrue());
            try t.expect(v8.Intrinsics.getObjects(context).?.len() > 0);
            creator.setDefaultContext(context);
        }
        // CreateBlob must run outside all handle scopes.
        break :make creator.createBlob(0);
    };
    defer blob.deinit();
    try t.expect(blob.slice().len > 0);
    params.snapshot_blob = &blob;
    const isolate = v8.Isolate.init(&params);
    defer isolate.deinit();
    isolate.enter();
    defer isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(isolate);
    defer h_scope.deinit();
    const context = v8.Context.init(isolate, null, null, null);
    context.enter();
    defer context.exit();
    isolate.lowMemoryNotification();
    const push = v8.Intrinsics.get(context, "ArrayPrototypePush").?;
    const all = v8.Intrinsics.getAll(context).?;
    try t.expect(all.get(context, v8.String.initUtf8(isolate, "ArrayPrototypePush").name.primitive.value).?.strictEquals(push.object.value));
    const array = v8.Array.init(isolate, 0);
    try t.expectEqual(@as(i32, 0), push.call(context, array.object.value, &.{}).?.i32Value(context).?);
    const restored = v8.Script.compile(context, v8.String.initUtf8(isolate, "Array.prototype.push"), null).?.run(context).?;
    try t.expect(push.object.value.strictEquals(restored));
    const inventory = v8.Intrinsics.getObjects(context).?;
    try t.expect(inventory.len() > 0);
    try t.expect(v8.Script.compile(context, v8.String.initUtf8(isolate, "Object.isFrozen(Array.prototype) && !Reflect.deleteProperty(globalThis, 'Date') && !Object.hasOwn(RegExp, '$1') && typeof RegExp[Symbol.species] === 'function'"), null).?.run(context).?.isTrue());
}

test "Intrinsics: raw contexts finalize complete graph and keep host globals extensible" {
    try withEnv(struct {
        /// Borrows env and its entered context/live HandleScope through return.
        /// Exposes only test-local GC-owned inventory; no resources escape.
        fn run(env: *Env) !void {
            const inventory = v8.Intrinsics.getObjects(env.context).?;
            env.setGlobal("inventory", inventory.object.value);
            env.setGlobal("segmentsPrototype", v8.Intrinsics.getPrototype(env.context, .intl_segments).?.value);
            env.setGlobal("segmentIteratorPrototype", v8.Intrinsics.getPrototype(env.context, .intl_segment_iterator).?.value);
            try t.expect(env.eval(
                \\Object.isFrozen(inventory) && inventory.length > 0 &&
                \\inventory.every(Object.isFrozen) &&
                \\Object.isExtensible(globalThis) &&
                \\Reflect.defineProperty(globalThis, 'hostGlobal', {value: 42, configurable: true}) &&
                \\Reflect.deleteProperty(globalThis, 'hostGlobal') &&
                \\['Date', 'Object', 'Array', 'Intl', 'RegExp', 'globalThis'].every(name => {
                \\  const d = Object.getOwnPropertyDescriptor(globalThis, name);
                \\  return !d.writable && !d.configurable &&
                \\    !Reflect.set(globalThis, name, () => {}) &&
                \\    !Reflect.deleteProperty(globalThis, name) &&
                \\    !Reflect.defineProperty(globalThis, name, {value: () => {}});
                \\}) &&
                \\['input','$_','lastMatch','$&','lastParen','$+','leftContext','$`',
                \\ 'rightContext',"$'",'$1','$2','$3','$4','$5','$6','$7','$8','$9']
                \\.every(name => !Object.hasOwn(RegExp, name)) &&
                \\RegExp[Symbol.species] === RegExp &&
                \\['WebAssembly', 'SharedArrayBuffer', 'Atomics', 'ShadowRealm']
                \\.every(name => !Object.hasOwn(globalThis, name))
            ).isTrue());
            try t.expect(env.eval(
                \\(() => {
                \\  const p = Object.getPrototypeOf;
                \\  const segments = new Intl.Segmenter().segment('x');
                \\  const hidden = [p(segments), p(segments[Symbol.iterator]()),
                \\    p([][Symbol.iterator]()), p(''[Symbol.iterator]()),
                \\    p(new Map().entries()), p(new Set().values()),
                \\    p(''.matchAll(/x/g)), p(function*(){}), p(p((function*(){})())),
                \\    p(async()=>{}), p(async function*(){}), p(p((async function*(){})())),
                \\    p(Iterator.from({next(){return {done:true}}})),
                \\    p([][Symbol.iterator]().map(x=>x))];
                \\  return hidden[0] === segmentsPrototype && hidden[1] === segmentIteratorPrototype &&
                \\    hidden.every(x => inventory.includes(x) && Object.isFrozen(x));
                \\})()
            ).isTrue());
        }
    }.run);
}

test "V8: initialize and ICU" {
    ensureV8();
    // Lazy provider registration is idempotent and never forces data expansion.
    try t.expect(v8.V8.initializeICU());
    try t.expect(v8.V8.initializeICU());
}

test "ICU: compressed data preserves multilingual Intl services" {
    try withEnv(struct {
        /// Borrows env and its entered context/live handle scope through this
        /// call; temporary script/value handles expire with that scope.
        fn run(env: *Env) !void {
            try t.expect(env.eval(
                \\(() => {
                \\  const locales = ['en', 'de', 'zh', 'ja', 'ar', 'th'];
                \\  for (const service of [Intl.NumberFormat, Intl.DateTimeFormat, Intl.Collator, Intl.Segmenter]) {
                \\    if (service.supportedLocalesOf(locales).length !== locales.length) return false;
                \\  }
                \\  if (new Intl.NumberFormat('de-DE').format(1234.5) !== '1.234,5') return false;
                \\  if (new Intl.Collator('de').compare('a', 'z') >= 0) return false;
                \\  if (new Intl.DateTimeFormat('en', {timeZone:'Asia/Tokyo', hour:'numeric', hourCycle:'h23'}).format(0) !== '09') return false;
                \\  if ([...new Intl.Segmenter('ja', {granularity:'grapheme'}).segment('あいう')].length !== 3) return false;
                \\  if ([...new Intl.Segmenter('th', {granularity:'word'}).segment('ภาษาไทย')].length < 2) return false;
                \\  return 'e\u0301'.normalize('NFC') === '\u00e9';
                \\})()
            ).isTrue());
        }
    }.run);
}

test "Platform: message loop pumps without work" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            // V8 15.2 may queue startup foreground tasks; drain them, then the loop must report idle.
            var drained: usize = 0;
            while (platform.pumpMessageLoop(env.isolate, false)) : (drained += 1) try t.expect(drained < 1000);
            try t.expect(!platform.pumpMessageLoop(env.isolate, false));
        }
    }.run);
}

// ------------------------------------------------------------------ Isolate / HandleScope / Context

test "Isolate: enter, current, data slots" {
    try withEnv(struct {
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
        fn run(env: *Env) !void {
            const global = env.context.getGlobal();
            try t.expect(global.set(env.context, env.name("answer").primitive.value, v8.Number.initInt(env.isolate, 42).numeric.primitive.value).?);
            try env.expectEval("answer", "42");

            const other = v8.Context.init(env.isolate, null, null, null);
            try t.expect(other.data.handle != env.context.data.handle);
        }
    }.run);
}

// ------------------------------------------------------------------ Strings, numbers, primitives

test "String: encodings and lengths" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const utf8 = v8.String.initUtf8(env.isolate, "héllo 🍏");
            try t.expectEqual(@as(c_int, 8), utf8.len()); // 🍏 is a surrogate pair
            try t.expectEqual(@as(usize, 11), utf8.lenUtf8(env.isolate));

            const one = v8.String.initOneByte(env.isolate, "abc");
            try t.expectEqual(@as(c_int, 3), one.len());

            const wide = v8.String.initTwoByte(env.isolate, &[_]u16{ 'h', 'i', 0xD83C, 0xDF4F });
            try t.expectEqual(@as(c_int, 4), wide.len()); // two code units for the emoji

            const static = v8.String.initOneByteStatic(env.isolate, "static");
            try t.expectEqual(@as(c_int, 6), static.len());

            var buf: [11]u8 = undefined;
            try t.expectEqual(@as(usize, 11), utf8.writeUtf8(env.isolate, &buf));
            try t.expectEqualStrings("héllo 🍏", &buf);
        }
    }.run);
}

test "Value: conversions" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const forty_two = env.eval("40 + 2");
            try t.expect(forty_two.isNumber());
            try t.expectEqual(@as(?u32, 42), forty_two.u32Value(env.context));
            try t.expectEqual(@as(?i32, 42), forty_two.i32Value(env.context));
            try t.expectEqual(@as(?i32, -1), env.eval("-1").i32Value(env.context));
            try t.expect(!env.eval("'text'").isNumber());
            try env.expectEval("[1, [2, 3]]", "1,2,3");
        }
    }.run);
}

test "Number, Numeric and Primitive" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            try t.expectEqual(@as(f64, 1.5), v8.Number.init(env.isolate, 1.5).Value());
            try t.expectEqual(@as(f64, -7), v8.Number.initInt(env.isolate, -7).Value());
            try t.expectEqual(@as(f64, 4294967295), v8.Number.initUInt(env.isolate, 4294967295).Value());

            const n = v8.Number.init(env.isolate, 3);
            try t.expect(n.numeric.primitive.value.isNumber());
        }
    }.run);
}

test "Primitive: null and undefined" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            env.setGlobal("n", v8.Primitive.initNull(env.isolate).value);
            env.setGlobal("u", v8.Primitive.initUndefined(env.isolate).value);
            try env.expectEval("n === null && u === undefined", "true");
        }
    }.run);
}

test "Name: strings are names" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const n = env.name("key");
            const back = try env.utf8(n.primitive.value);
            defer t.allocator.free(back);
            try t.expectEqualStrings("key", back);
        }
    }.run);
}

test "External: round-trips a native pointer" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            var payload: u64 = 0xdead_beef;
            const ext = v8.External.init(env.isolate, &payload);
            const got: *u64 = @ptrCast(@alignCast(ext.pointer().?));
            try t.expectEqual(@as(u64, 0xdead_beef), got.*);
        }
    }.run);
}

test "Data: handles compare by identity" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const a = env.eval("({})");
            const same = v8.Data.from_opaque(a.data.handle).?;
            try t.expectEqual(a.data.handle, same.handle);
        }
    }.run);
}

// ------------------------------------------------------------------ Arrays

test "Array: construct, length and elements" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const empty = v8.Array.init(env.isolate, 3);
            try t.expectEqual(@as(u32, 3), empty.len());

            const items = [_]v8.Value{
                v8.Number.initInt(env.isolate, 1).numeric.primitive.value,
                env.str("two").name.primitive.value,
            };
            const arr = v8.Array.with_elements(env.isolate, &items).?;
            try t.expectEqual(@as(u32, 2), arr.len());
            env.setGlobal("arr", arr.object.value);
            try env.expectEval("arr.join('-')", "1-two");
        }
    }.run);
}

test "PrimitiveArray: set and get" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const arr = v8.PrimitiveArray.init(env.isolate, 2);
            const forty = v8.Number.initInt(env.isolate, 40).numeric.primitive;
            arr.set(env.isolate, 1, forty);
            const got = arr.get(env.isolate, 1);
            try t.expectEqual(@as(?i32, 40), got.value.i32Value(env.context));
        }
    }.run);
}

// ------------------------------------------------------------------ Object / PropertyDescriptor

fn num(env: *Env, n: i32) v8.Value {
    return v8.Number.initInt(env.isolate, n).numeric.primitive.value;
}

test "Object: get, set, index access" {
    try withEnv(struct {
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
        fn run(env: *Env) !void {
            const date = v8.Object.from_opaque(env.eval("new Date(0)").data.handle).?;
            const ctor = date.getConstructorName();
            const name = try env.utf8(ctor.name.primitive.value);
            defer t.allocator.free(name);
            try t.expectEqualStrings("Date", name);

            const proto = date.getPrototype().?;
            env.setGlobal("proto", proto);
            try env.expectEval("proto === Date.prototype", "true");

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

// ------------------------------------------------------------------ Functions and callback infos

var observed_arg_count: c_int = -1;
var observed_construct: bool = false;
var observed_data: ?i32 = null;

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

fn cbConstruct(info: v8.FunctionCallbackInfo) callconv(.c) void {
    observed_construct = info.isConstructCall();
}

var observed_new_target_is_function: bool = false;
fn cbThisAndTarget(info: v8.FunctionCallbackInfo) callconv(.c) void {
    const ctx = info.isolate().getCurrentContext();
    // `this` is a fresh object for `new`, and new.target is the constructor itself.
    _ = info.this().set(ctx, v8.String.initUtf8(info.isolate(), "tag").name.primitive.value, v8.Number.initInt(info.isolate(), 5).numeric.primitive.value);
    observed_new_target_is_function = info.isConstructCall() and !info.newTarget().isNumber();
}

fn cbUndefined(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setUndefined();
}

test "FunctionTemplate: builder, instantiation and construct calls" {
    try withEnv(struct {
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

// ------------------------------------------------------------------ ReturnValue

fn cbReturnString(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.set(v8.String.initUtf8(info.isolate(), "str").name.primitive.value);
    // The value just stored can be read back.
    observed_data = if (rv.get()) |v| v.i32Value(info.isolate().getCurrentContext()) else null;
}
fn cbReturnBool(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setBool(true);
}
fn cbReturnInt32(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setInt32(-5);
}
fn cbReturnUint32(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setUint32(4000000000);
}
fn cbReturnDouble(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setDouble(0.25);
}
fn cbReturnNull(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setNull();
}
fn cbReturnEmptyString(info: v8.FunctionCallbackInfo) callconv(.c) void {
    var rv = info.retval();
    rv.setEmptyString();
}

test "ReturnValue: every setter" {
    try withEnv(struct {
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

// ------------------------------------------------------------------ PropertyCallbackInfo

var accessor_saw_holder_match: bool = false;
var accessor_should_throw: bool = true;

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
fn setterRecord(_: v8.Name, value: v8.Value, info: *const v8.PropertyCallbackInfo) callconv(.c) void {
    setter_received = value.i32Value(info.isolate().getCurrentContext());
}

test "PropertyCallbackInfo: accessor setter receives the assigned value" {
    try withEnv(struct {
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

// ------------------------------------------------------------------ Templates

test "ObjectTemplate and Template.set" {
    try withEnv(struct {
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

// ------------------------------------------------------------------ Global (persistent) handles

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

// ------------------------------------------------------------------ Promises

test "Promise: resolved, pending and rejected states" {
    try withEnv(struct {
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
        fn run(env: *Env) !void {
            env.isolate.setMicrotasksPolicy(.Explicit);
            _ = env.eval("globalThis.ran = false; Promise.resolve().then(() => { ran = true; })");
            try env.expectEval("ran", "false");
            env.isolate.performMicrotasksCheckpoint();
            try env.expectEval("ran", "true");
        }
    }.run);
}

// ------------------------------------------------------------------ FixedArray

test "FixedArray: length and element access (via a PrimitiveArray's backing store)" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const prim = v8.PrimitiveArray.init(env.isolate, 3);
            prim.set(env.isolate, 2, v8.Number.initInt(env.isolate, 31).numeric.primitive);
            const fixed: v8.FixedArray = .{ .data = prim.data };
            try t.expectEqual(@as(c_int, 3), fixed.len());
            const third = v8.Value{ .data = fixed.get(2).? };
            try t.expectEqual(@as(?i32, 31), third.i32Value(env.context));
        }
    }.run);
}

// ------------------------------------------------------------------ Script / ScriptOrigin / TryCatch / Message

/// Runs `src` as `name`; returns null when it throws (the caller's TryCatch holds the error).
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

fn cbCaptureStack(info: v8.FunctionCallbackInfo) callconv(.c) void {
    const trace = v8.StackTrace.getCurrentStackTrace(info.isolate(), 8);
    current_trace_frames = trace.getFrameCount();
    if (v8.StackTrace.getCurrentScriptNameOrSourceUrl(info.isolate())) |name| current_trace_name_len = name.len();
}

test "StackTrace: current stack from inside a native callback" {
    try withEnv(struct {
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

// ------------------------------------------------------------------ Termination

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

// ------------------------------------------------------------------ Layout facts shared with C++

test "Layouts: extern structs match the C++ sizes" {
    try t.expectEqual(@as(usize, binding.sizes.HandleScope), @sizeOf(v8.HandleScope));
    try t.expectEqual(@as(usize, binding.sizes.TryCatch), @sizeOf(v8.TryCatch));
    try t.expectEqual(@as(usize, binding.sizes.ScriptOrigin), @sizeOf(v8.ScriptOrigin));
    try t.expectEqual(@as(usize, binding.sizes.PropertyDescriptor), @sizeOf(v8.PropertyDescriptor));
    try t.expectEqual(@as(usize, binding.sizes.Isolate_CreateParams), @sizeOf(v8.Isolate.CreateParams));
    try t.expectEqual(@as(usize, binding.sizes.ResourceConstraints), @sizeOf(v8.ResourceConstraints));
    try t.expectEqual(@as(usize, binding.sizes.HeapStatistics), @sizeOf(v8.HeapStatistics));
    try t.expectEqual(@as(usize, binding.sizes.CFunction), @sizeOf(v8.CFunction));
    try t.expectEqual(@as(usize, binding.sizes.CTypeInfo), @sizeOf(v8.CTypeInfo));
    try t.expectEqual(@as(usize, 4), @sizeOf(v8.PropertyAttribute));
}

// ------------------------------------------------------------------ Host callbacks

var import_attribute_count: c_int = -1;

fn cbHostImport(
    ctx: v8.Context,
    _: v8.Data,
    _: v8.Value,
    specifier: v8.String,
    attributes: v8.FixedArray,
) callconv(.c) v8.MaybeHandle {
    import_attribute_count = attributes.len();
    const resolver = v8.Promise.Resolver.init(ctx).?;
    _ = resolver.reject(ctx, specifier.name.primitive.value);
    return resolver.getPromise().object.value.data.handle;
}

fn cbImportMeta(_: v8.Context, _: v8.Module, _: v8.Object) callconv(.c) void {}

test "Isolate: dynamic import() reaches the host callback" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            import_attribute_count = -1;
            env.isolate.setMicrotasksPolicy(.Explicit);
            env.isolate.setHostInitializeImportMetaObjectCallback(cbImportMeta);
            env.isolate.setHostImportModuleDynamicallyCallback(cbHostImport);

            _ = env.eval("globalThis.err = null; import('virtual:thing').catch(e => { err = e; })");
            env.isolate.performMicrotasksCheckpoint();
            try env.expectEval("err", "virtual:thing");
            try t.expectEqual(@as(c_int, 0), import_attribute_count);
        }
    }.run);
}

// ------------------------------------------------------------------ Value / primitives group

test "Value: type predicates, conversions and equality" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const ctx = env.context;
            try t.expect(env.eval("undefined").isUndefined());
            try t.expect(env.eval("null").isNullOrUndefined());
            try t.expect(env.eval("true").isTrue());
            try t.expect(env.eval("[]").isArray());
            try t.expect(env.eval("new Map()").isMap());
            try t.expect(env.eval("Symbol()").isSymbol());
            try t.expect(env.eval("5").isInt32());
            try t.expect(env.eval("'a'").isString());
            try t.expect(env.eval("'a'").data.isPrimitive());

            const n = env.eval("'42'");
            try t.expectEqual(@as(f64, 42), n.numberValue(ctx).?);
            try t.expectEqual(@as(i64, 42), n.integerValue(ctx).?);
            try t.expectEqual(@as(u32, 42), n.toUint32(ctx).?.value());
            try t.expectEqual(@as(i32, 42), n.toInt32(ctx).?.value());
            try t.expect(n.booleanValue(env.isolate));
            try t.expect(env.eval("1").strictEquals(env.eval("1")));
            try t.expect(!env.eval("1").strictEquals(env.eval("'1'")));
            try t.expect(env.eval("NaN").sameValue(env.eval("NaN")));
            const ty = try env.utf8(env.eval("1").typeOf(env.isolate).name.primitive.value);
            defer t.allocator.free(ty);
            try t.expectEqualStrings("number", ty);
            try t.expect(env.eval("[]").instanceOf(ctx, env.eval("Array").toObject(ctx).?).?);
        }
    }.run);
}

test "Integer/Boolean/BigInt/Date/Symbol/Private/Name wrappers" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const iso = env.isolate;
            try t.expectEqual(@as(i64, -7), v8.Integer.init(iso, -7).value());
            try t.expectEqual(@as(i64, 4000000000), v8.Integer.initFromUnsigned(iso, 4000000000).value());
            try t.expect(v8.Boolean.init(iso, true).primitive.value.isTrue());

            const big = v8.BigInt.init(iso, -5);
            var lossless: bool = false;
            try t.expectEqual(@as(i64, -5), big.int64Value(&lossless));
            try t.expect(lossless);
            var words: [2]u64 = undefined;
            const r = big.toWordsArray(&words);
            try t.expect(r.negative);
            try t.expectEqual(@as(usize, 1), r.word_count);
            try t.expectEqual(@as(u64, 5), words[0]);
            const b2 = v8.BigInt.initFromWords(env.context, false, &.{ 1, 2 }).?;
            try t.expectEqual(@as(usize, 2), b2.wordCount());
            try t.expectEqual(@as(u64, 9), v8.BigInt.initFromUnsigned(iso, 9).uint64Value(null));

            const d = v8.Date.init(env.context, 1234).?;
            try t.expectEqual(@as(f64, 1234), d.valueOf());

            const s1 = v8.Symbol.init(iso, env.str("desc"));
            const desc = try env.utf8(s1.description(iso));
            defer t.allocator.free(desc);
            try t.expectEqualStrings("desc", desc);
            try t.expect(v8.Symbol.getIterator(iso).name.primitive.value.isSymbol());

            const p = v8.Private.init(iso, env.str("pv"));
            try t.expect(p.data.isPrivate());
            const pn = try env.utf8(p.name());
            defer t.allocator.free(pn);
            try t.expectEqualStrings("pv", pn);
            _ = env.name("x").getIdentityHash();
        }
    }.run);
}

// Newly completed wrappers: exercise conversion, mutation, failure, and lifetimes.
test "Map and Set: mutation and empty results" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const key = env.str("key").name.primitive.value;
            const value = env.eval("42");
            const map = v8.Map.init(env.isolate).?;
            try t.expectEqual(@as(usize, 0), map.size());
            _ = map.set(env.context, key, value).?;
            try t.expect(map.has(env.context, key).?);
            try t.expect(map.get(env.context, key).?.strictEquals(value));
            try t.expectEqual(@as(u32, 2), map.asArray().?.len());
            try t.expect(map.delete(env.context, key).?);
            try t.expect(!map.delete(env.context, key).?);
            try t.expect(map.get(env.context, key).?.isUndefined());
            map.clear();
            const set = v8.Set.init(env.isolate).?;
            _ = set.add(env.context, value).?;
            _ = set.add(env.context, value).?;
            try t.expectEqual(@as(usize, 1), set.size());
            try t.expect(set.has(env.context, value).?);
            try t.expect(set.delete(env.context, value).?);
            set.clear();
            try t.expectEqual(@as(usize, 0), set.size());
        }
    }.run);
}

test "ArrayBuffer and typed views: shared storage, offsets and detachment" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const buf = v8.ArrayBuffer.newWithByteLength(env.isolate, 16).?;
            try t.expectEqual(@as(usize, 16), buf.byteLength());
            var backing = buf.getBackingStore();
            defer backing.deinit();
            const alias = v8.ArrayBuffer.newWithBackingStore(env.isolate, &backing).?;
            try t.expectEqual(buf.data(), alias.data());
            const bytes: [*]u8 = @ptrCast(buf.data().?);
            bytes[4] = 77;
            const view = v8.Uint8Array.init(buf, 4, 8).?;
            try t.expectEqual(@as(usize, 8), view.typedArray.length());
            try t.expectEqual(@as(usize, 4), view.typedArray.arrayBufferView.byteOffset());
            try t.expect(view.typedArray.arrayBufferView.hasBuffer());
            var copied: [8]u8 = undefined;
            try t.expectEqual(@as(usize, 8), view.typedArray.arrayBufferView.copyContents(&copied, copied.len));
            try t.expectEqual(@as(u8, 77), copied[0]);
            const dv = v8.DataView.init(buf, 0, 4).?;
            try t.expectEqual(@as(usize, 4), dv.arrayBufferView.byteLength());
            inline for (.{ v8.Int8Array, v8.Uint8ClampedArray, v8.Int16Array, v8.Uint16Array, v8.Int32Array, v8.Uint32Array, v8.Float16Array, v8.Float32Array, v8.Float64Array, v8.BigInt64Array, v8.BigUint64Array }) |T| {
                try t.expectEqual(@as(usize, 1), T.init(buf, 0, 1).?.typedArray.length());
            }
            try t.expect(buf.isDetachable());
            try t.expect(buf.detach(null).?);
            try t.expect(buf.wasDetached());
            try t.expectEqual(@as(usize, 0), view.typedArray.length());
            const shared = v8.SharedArrayBuffer.newWithByteLength(env.isolate, 8).?;
            try t.expectEqual(@as(usize, 8), shared.byteLength());
        }
    }.run);
}

test "String ValueView, persistent references and execution scopes" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const string = env.str("hello");
            {
                var view: v8.String.ValueView = undefined;
                view.init(env.isolate, string);
                defer view.deinit();
                try t.expectEqualStrings("hello", view.bytes().?);
                try t.expect(view.words() == null);
            }
            const wide = v8.String.initTwoByte(env.isolate, &.{0x4e2d});
            {
                var view: v8.String.ValueView = undefined;
                view.init(env.isolate, wide);
                defer view.deinit();
                try t.expectEqualSlices(u16, &.{0x4e2d}, view.words().?);
            }
            var eternal: v8.Eternal = undefined;
            eternal.init();
            defer eternal.deinit();
            try t.expect(eternal.isEmpty());
            eternal.set(env.isolate, string.name.primitive.value.data);
            try t.expect(eternal.get(env.isolate).?.eq(string.name.primitive.value.data));
            eternal.clear();
            try t.expect(eternal.isEmpty());
            var traced: v8.TracedReference = undefined;
            traced.init();
            defer traced.deinit();
            traced.reset(env.isolate, string.name.primitive.value.data);
            try t.expect(traced.get(env.isolate).?.eq(string.name.primitive.value.data));
            var disallow: v8.Isolate.DisallowJavascriptExecutionScope = undefined;
            disallow.init(env.isolate, .throw);
            defer disallow.deinit();
            var allow: v8.Isolate.AllowJavascriptExecutionScope = undefined;
            allow.init(env.isolate);
            defer allow.deinit();
            try env.expectEval("1 + 2", "3");
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "JSON, RegExp, Proxy and Function invocation" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            const parsed = v8.JSON.parse(env.context, env.str("{\"answer\":42}")).?;
            const json = v8.JSON.stringify(env.context, parsed).?;
            const text = try env.utf8(json.name.primitive.value);
            defer t.allocator.free(text);
            try t.expectEqualStrings("{\"answer\":42}", text);
            const regex = v8.RegExp.init(env.context, env.str("a+"), 0).?;
            try t.expect(regex.exec(env.context, env.str("aaa")) != null);
            const target = parsed.toObject(env.context).?;
            const handler = env.eval("({})").toObject(env.context).?;
            const proxy = v8.Proxy.init(env.context, target, handler).?;
            try t.expect(proxy.getTarget().?.strictEquals(parsed));
            try t.expect(!proxy.isRevoked());
            proxy.revoke();
            try t.expect(proxy.isRevoked());
            const function = v8.Function.from_opaque(env.eval("(x => x + 1)").data.handle).?;
            try t.expectEqual(function.scriptId(), function.getScriptOrigin().scriptId());
            const result = function.call(env.context, env.eval("undefined"), &.{env.eval("41")}).?;
            try t.expectEqual(@as(f64, 42), result.numberValue(env.context).?);
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();
            try t.expect(v8.JSON.parse(env.context, env.str("invalid json")) == null);
            try t.expect(tc_scope.hasCaught());
        }
    }.run);
}

var module_dependency: v8.MaybeHandle = null;
fn resolveTestModule(_: v8.Context, _: v8.String, _: v8.FixedArray, _: v8.Module) callconv(.c) v8.MaybeHandle {
    return module_dependency;
}

test "ScriptCompiler: script caching, module requests and evaluation" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            var source: v8.ScriptCompiler.Source = undefined;
            source.init(env.str("6 * 7"), null, null);
            defer source.deinit();
            const script = v8.ScriptCompiler.compile(env.context, &source, 0, 0).?;
            try t.expectEqual(@as(f64, 42), script.run(env.context).?.numberValue(env.context).?);
            const unbound = script.getUnboundScript().?;
            const cache = unbound.createCodeCache().?;
            defer cache.deinit();
            try t.expect(unbound.bindToCurrentContext() != null);
            var module_source: v8.ScriptCompiler.Source = undefined;
            var origin = v8.ScriptOrigin.init(env.str("test.mjs").name.primitive.value, 0, 0, false, -1, null, false, false, true, null);
            module_source.init(env.str("import { value } from 'dep'; export const answer = value;"), &origin, null);
            defer module_source.deinit();
            const module = v8.ScriptCompiler.compileModule(env.isolate, &module_source, 0, 0).?;
            try t.expect(module.isSourceTextModule());
            const requests = module.getModuleRequests().?;
            try t.expectEqual(@as(c_int, 1), requests.len());
            const request = v8.ModuleRequest.from_opaque(requests.get(0).?.handle).?;
            const specifier = try env.utf8(request.getSpecifier().?.name.primitive.value);
            defer t.allocator.free(specifier);
            try t.expectEqualStrings("dep", specifier);
            var dependency_source: v8.ScriptCompiler.Source = undefined;
            dependency_source.init(env.str("export const value = 42;"), &origin, null);
            defer dependency_source.deinit();
            const dependency = v8.ScriptCompiler.compileModule(env.isolate, &dependency_source, 0, 0).?;
            module_dependency = dependency.data.handle;
            defer module_dependency = null;
            var location: v8.Location = undefined;
            module.sourceOffsetToLocation(0, &location);
            try t.expectEqual(@as(c_int, 0), location.getLineNumber());
            try t.expect(module.instantiateModule(env.context, resolveTestModule, null).?);
            try t.expect(module.evaluate(env.context).?.isPromise());
            const namespace = module.getModuleNamespace().?.toObject(env.context).?;
            try t.expectEqual(@as(f64, 42), namespace.get(env.context, env.str("answer").name.primitive.value).?.numberValue(env.context).?);
        }
    }.run);
}

test "Wasm compiled-module ownership and heap-space statistics" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            var bytes = [_]u8{ 0, 'a', 's', 'm', 1, 0, 0, 0 };
            const module = v8.WasmModuleObject.compile(env.isolate, &bytes, bytes.len).?;
            const compiled = module.getCompiledModule().?;
            defer compiled.deinit();
            var length: usize = 0;
            const wire = compiled.getWireBytesRef(&length).?;
            try t.expectEqualSlices(u8, &bytes, wire[0..length]);
            try t.expect(v8.WasmModuleObject.fromCompiledModule(env.isolate, compiled) != null);
            var stats: v8.HeapSpaceStatistics = undefined;
            try t.expect(env.isolate.numberOfHeapSpaces() > 0);
            try t.expect(env.isolate.getHeapSpaceStatistics(&stats, 0));
            try t.expect(stats.space_name != null);
            try t.expect(stats.space_size >= stats.space_used_size);
        }
    }.run);
}

test "zero values: native handles, arrays, callbacks and persistent locals" {
    try withEnv(struct {
        fn run(env: *Env) !void {
            const zero = env.eval("0");
            try t.expect(zero.isNumber());
            try t.expect(zero.isInt32());
            try t.expect(zero.data.isValue());
            try t.expect(zero.data.isNumber());
            try t.expect(zero.strictEquals(env.eval("0")));
            try t.expectEqual(@as(?i32, 0), zero.i32Value(env.context));
            try t.expectEqual(@as(f64, 0), v8.Number.init(env.isolate, 0).Value());
            try t.expectEqual(@as(i64, 0), v8.Integer.init(env.isolate, 0).value());
            const function = v8.Function.from_opaque(env.eval("(x => x)").data.handle).?;
            try t.expectEqual(@as(?i32, 0), function.call(env.context, env.eval("undefined"), &.{zero}).?.i32Value(env.context));
            const array = v8.Array.with_elements(env.isolate, &.{zero}).?;
            try t.expectEqual(@as(?i32, 0), array.object.getIndex(env.context, 0).?.i32Value(env.context));
            const global = v8.Global.new(env.isolate, zero.data);
            defer global.deinit();
            try t.expectEqual(@as(?i32, 0), (v8.Value{ .data = global.local(env.isolate) }).i32Value(env.context));
            const local = v8.localNew(env.isolate, zero);
            try t.expectEqual(@as(?i32, 0), local.i32Value(env.context));
            const typed = v8.Global.Of(v8.Value).new(env.isolate, zero);
            defer typed.deinit();
            try t.expectEqual(@as(?i32, 0), typed.deref().i32Value(env.context));
            const raw = v8.toRawLocal(zero.data.handle);
            try t.expectEqual(zero.data.handle, v8.fromRawLocal(raw));
        }
    }.run);
}

// Local V8 scopes are released before return; no resources escape.
test "V8: native strict default applies without source rewriting" {
    try withEnv(struct {
        /// Local V8 scopes are released before return; no resources escape.
        fn run(env: *Env) !void {
            try env.expectEval("(function(){return this})() === undefined", "true");
            try env.expectEval("#!/usr/bin/env js\n(function(){return this})() === undefined", "true");
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();
            try t.expect(env.tryEval("implicitNativeGlobal = 1") == null);
            try t.expect(tc_scope.hasCaught());
        }
    }.run);
}
