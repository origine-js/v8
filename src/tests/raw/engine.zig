const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;
const ensureV8 = support.ensureV8;

test "V8: linked engine is 15.8.30" {
    try t.expect(std.mem.startsWith(u8, v8.V8.getVersion(), "15.8.30"));
}

test "WebAssembly: frozen namespace compiles and runs a module" {
    try t.expect(v8.has_webassembly);
    try t.expect(@hasDecl(v8.wasm, "WasmModuleObject"));
    try withEnv(struct {
        /// Borrows the entered fixture and its local handles through return;
        /// creates only context-owned JavaScript objects, retaining no host resources.
        fn run(env: *Env) !void {
            try t.expect(env.eval(
                \\Object.isFrozen(WebAssembly) && Object.isFrozen(WebAssembly.Module) &&
                \\Object.isFrozen(WebAssembly.Instance.prototype) &&
                \\(() => {
                \\  const bytes = new Uint8Array([0,97,115,109,1,0,0,0,1,7,1,96,2,127,127,1,127,
                \\    3,2,1,0,7,7,1,3,97,100,100,0,0,10,9,1,7,0,32,0,32,1,106,11]);
                \\  const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes));
                \\  return instance.exports.add(3, 4) === 7;
                \\})()
            ).isTrue());
        }
    }.run);
}

test "Isolate: blocking Atomics.wait defaults off and can be toggled" {
    try withEnv(struct {
        /// Borrows the entered fixture and its local handles through return;
        /// creates only context-owned JavaScript objects, retaining no host resources.
        fn run(env: *Env) !void {
            try t.expect(env.eval(
                \\globalThis.cells = new Int32Array(new SharedArrayBuffer(4));
                \\globalThis.waitDenied = () => {
                \\  try { Atomics.wait(cells, 0, 0, 0); return false; }
                \\  catch (e) { return e instanceof TypeError; }
                \\};
                \\waitDenied() && Atomics.waitAsync(cells, 0, 1).value === 'not-equal'
            ).isTrue());
            env.isolate.setAllowExplicitBlockingApi(true);
            try t.expect(env.eval("Atomics.wait(cells, 0, 0, 0) === 'timed-out'").isTrue());
            env.isolate.setAllowExplicitBlockingApi(false);
            try t.expect(env.eval("waitDenied() && Atomics.add(cells, 0, 1) === 0").isTrue());
        }
    }.run);
}

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
            context.setStackTraceLimit(.{ .limited = 7 });
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
    try t.expectEqual(@as(u31, 7), context.getStackTraceLimit().limited);
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

var snapshot_dependency: v8.MaybeHandle = null;

/// Resolves every import to the test's single dependency module; borrows nothing
/// and retains nothing. Valid only while `snapshot_dependency` is set.
fn resolveSnapshotDependency(_: v8.Context, _: v8.String, _: v8.FixedArray, _: v8.Module) callconv(.c) v8.MaybeHandle {
    return snapshot_dependency;
}

// Local V8 scopes are released before return; the blob is freed on every path.
test "Module: an evaluated ES module graph survives a context snapshot without re-evaluating" {
    ensureV8();
    const evaluated: u32 = 4;
    const aba = v8.ArrayBuffer.Allocator.initDefault();
    defer aba.deinit();
    var params = v8.Isolate.CreateParams.init();
    params.array_buffer_allocator = aba;
    var main_index: usize = undefined;
    var dependency_index: usize = undefined;
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
            var origin = v8.ScriptOrigin.init(v8.String.initUtf8(isolate, "init.mjs").name.primitive.value, 0, 0, false, -1, null, false, false, true, null);
            var dependency_source: v8.ScriptCompiler.Source = undefined;
            dependency_source.init(v8.String.initUtf8(isolate, "export let count = 0; export function bump() { return ++count; }"), &origin, null);
            defer dependency_source.deinit();
            const dependency = v8.ScriptCompiler.compileModule(isolate, &dependency_source, 0, 0).?;
            var main_source: v8.ScriptCompiler.Source = undefined;
            main_source.init(v8.String.initUtf8(isolate, "import { bump } from 'dep'; export const first = bump();"), &origin, null);
            defer main_source.deinit();
            const main_module = v8.ScriptCompiler.compileModule(isolate, &main_source, 0, 0).?;
            snapshot_dependency = dependency.data.handle;
            defer snapshot_dependency = null;
            try t.expect(main_module.instantiateModule(context, resolveSnapshotDependency, null).?);
            try t.expect(main_module.evaluate(context).?.isPromise());
            try t.expectEqual(evaluated, main_module.getStatus());
            creator.setDefaultContext(context);
            main_index = creator.addDataToContext(context, main_module.data);
            dependency_index = creator.addDataToContext(context, dependency.data);
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
    const main_data = context.getDataFromSnapshotOnce(main_index).?;
    const dependency_data = context.getDataFromSnapshotOnce(dependency_index).?;
    try t.expect(main_data.isModule());
    const main_module = v8.Module.from_opaque(main_data.handle).?;
    const dependency = v8.Module.from_opaque(dependency_data.handle).?;
    try t.expectEqual(evaluated, main_module.getStatus());
    try t.expectEqual(evaluated, dependency.getStatus());
    // Evaluating again must not run the body a second time.
    _ = main_module.evaluate(context);
    const namespace = main_module.getModuleNamespace().?.toObject(context).?;
    try t.expectEqual(@as(f64, 1), namespace.get(context, v8.String.initUtf8(isolate, "first").name.primitive.value).?.numberValue(context).?);
    // The dependency's state carried over: the next bump continues from 1.
    const dependency_namespace = dependency.getModuleNamespace().?.toObject(context).?;
    const bump = v8.Function.from_opaque(dependency_namespace.get(context, v8.String.initUtf8(isolate, "bump").name.primitive.value).?.data.handle).?;
    try t.expectEqual(@as(f64, 2), bump.call(context, v8.Primitive.initUndefined(isolate).value, &.{}).?.numberValue(context).?);
}

test "Date: only Date.now remains and Temporal replaces calendar functionality" {
    try withEnv(struct {
        /// Borrows env and its entered context/live HandleScope through return.
        /// Evaluates test-local scripts only; no resources escape.
        fn run(env: *Env) !void {
            try t.expect(env.eval(
                \\typeof Date.now() === 'number' && Date.now() > 0 &&
                \\Object.getOwnPropertyNames(Date).sort().join() === 'length,name,now,prototype' &&
                \\Object.getOwnPropertyNames(Date.prototype).join() === 'constructor' &&
                \\Object.getOwnPropertySymbols(Date.prototype).length === 0 &&
                \\Object.isFrozen(Date) && Object.isFrozen(Date.prototype) &&
                \\[() => new Date(), () => Date(), () => new Date(0), () => Reflect.construct(Date, [])]
                \\.every(f => { try { f(); return false; } catch (e) { return e instanceof TypeError; } }) &&
                \\typeof Temporal.Now.instant().epochMilliseconds === 'number' &&
                \\typeof Intl.DateTimeFormat('en', {timeZone: 'UTC'}).format(0) === 'string'
            ).isTrue());
        }
    }.run);
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
                \\['Date', 'Object', 'Array', 'Intl', 'RegExp', 'SharedArrayBuffer', 'Atomics', 'globalThis'].every(name => {
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
                \\typeof SharedArrayBuffer === 'function' &&
                \\Object.isFrozen(SharedArrayBuffer.prototype) &&
                \\typeof Atomics === 'object' && Object.isFrozen(Atomics) &&
                \\!Object.hasOwn(globalThis, 'ShadowRealm') &&
                \\typeof WebAssembly === 'object' && Object.isFrozen(WebAssembly)
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

test "V8: general allocations come from mimalloc" {
    var env: Env = undefined;
    env.start();
    defer env.stop();
    // i::Isolate is allocated with base::AlignedAlloc, which the V8 patch routes to mimalloc.
    try t.expect(@import("@mimalloc").mi_is_in_heap_region(env.isolate.handle));
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
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            // V8 15.2 may queue startup foreground tasks; drain them, then the loop must report idle.
            var drained: usize = 0;
            while (@import("../support.zig").engine.platform.pumpMessageLoop(env.isolate, false)) : (drained += 1) try t.expect(drained < 1000);
            try t.expect(!@import("../support.zig").engine.platform.pumpMessageLoop(env.isolate, false));
        }
    }.run);
}
