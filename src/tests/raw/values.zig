const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

test "Value: type predicates, conversions and equality" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
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

test "Integer/Boolean/BigInt/Symbol/Private/Name wrappers" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
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
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
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
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
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
            const shared_view = v8.Uint8Array.init(shared, 2, 4).?;
            const shared_base = shared_view.typedArray.arrayBufferView.buffer().?;
            try t.expect(shared_base.object.value.isSharedArrayBuffer());
            try t.expectEqual(@as(usize, 8), shared_base.byteLength());
            var shared_backing = shared_base.getBackingStore();
            defer shared_backing.deinit();
            try t.expect(shared_backing.a != null);
            try t.expectEqual(v8.ArrayBufferBase.fromBuffer(shared).data(), shared_base.data());
            const shared_data_view = v8.DataView.init(shared_base, 0, 4).?;
            try t.expectEqual(@as(usize, 4), shared_data_view.arrayBufferView.byteLength());
        }
    }.run);
}

test "String ValueView, persistent references and execution scopes" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
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
            const regex = v8.RegExp.init(env.context, env.str("a+"), .{}).?;
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
/// Accepts callback values; returns an empty local handle and retains no resources.
fn resolveTestModule(_: v8.Context, _: v8.String, _: v8.FixedArray, _: v8.Module) callconv(.c) v8.MaybeHandle {
    return module_dependency;
}

test "ScriptCompiler: script caching, module requests and evaluation" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
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

test "ScriptCompiler: a module code cache is consumed for equal source and rejected otherwise" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with its
        /// HandleScope. The test-owned cache bytes are copied before the producing cache is
        /// released; nothing escapes to the caller.
        fn run(env: *Env) !void {
            const text = "export const answer = () => { let n = 0; for (let i = 0; i < 4; i++) n += i; return n; };";
            var origin = v8.ScriptOrigin.init(env.str("cache.mjs").name.primitive.value, 0, 0, false, -1, null, false, false, true, null);
            var produce_source: v8.ScriptCompiler.Source = undefined;
            produce_source.init(env.str(text), &origin, null);
            defer produce_source.deinit();
            const module = v8.ScriptCompiler.compileModule(env.isolate, &produce_source, 0, 0).?;
            const cache = module.getUnboundModuleScript().?.createCodeCache().?;
            defer cache.deinit();
            const bytes = v8.ScriptCompiler.CachedData.bytes(cache.handle);
            try t.expect(bytes.len > 0);
            const copy = try t.allocator.dupe(u8, bytes);
            defer t.allocator.free(copy);

            // Same source: accepted, and the module behaves the same.
            var accepted: v8.ScriptCompiler.Source = undefined;
            accepted.init(env.str(text), &origin, v8.ScriptCompiler.CachedData.init(copy.ptr, @intCast(copy.len)));
            defer accepted.deinit();
            const consumed = v8.ScriptCompiler.compileModule(env.isolate, &accepted, 1, 0).?;
            try t.expect(!v8.ScriptCompiler.CachedData.rejected(accepted.getCachedData().?));
            try t.expect(consumed.instantiateModule(env.context, resolveTestModule, null).?);
            try t.expect(consumed.evaluate(env.context).?.isPromise());

            // A source of another length is refused and compiles from scratch.
            var rejected: v8.ScriptCompiler.Source = undefined;
            rejected.init(env.str(text ++ " "), &origin, v8.ScriptCompiler.CachedData.init(copy.ptr, @intCast(copy.len)));
            defer rejected.deinit();
            try t.expect(v8.ScriptCompiler.compileModule(env.isolate, &rejected, 1, 0) != null);
            try t.expect(v8.ScriptCompiler.CachedData.rejected(rejected.getCachedData().?));
        }
    }.run);
}

test "Wasm compiled-module ownership and heap-space statistics" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            if (comptime v8.has_webassembly) {
                var bytes = [_]u8{ 0, 'a', 's', 'm', 1, 0, 0, 0 };
                const module = v8.wasm.WasmModuleObject.compile(env.isolate, &bytes, bytes.len).?;
                const compiled = module.getCompiledModule().?;
                defer compiled.deinit();
                var length: usize = 0;
                const wire = compiled.getWireBytesRef(&length).?;
                try t.expectEqualSlices(u8, &bytes, wire[0..length]);
                try t.expect(v8.wasm.WasmModuleObject.fromCompiledModule(env.isolate, compiled) != null);
            }
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
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
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
