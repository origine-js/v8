const std = @import("std");
const t = std.testing;
const v8 = @import("../v8.zig");
const m = @import("../managed.zig");
const mimalloc = @import("../mimalloc.zig");

/// Borrows scope/source through evaluation; the temporary V8 handles are released
/// before return. Retains no resources.
fn check(scope: *m.Scope, source: []const u8) !void {
    const value = try scope.eval(source, "test:check", null);
    defer value.deinit();
    scope.runtime.isolate.enter();
    defer scope.runtime.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(scope.runtime.isolate);
    defer h_scope.deinit();
    try t.expect(value.deref().isTrue());
}

// Local V8 scopes are released before return; no resources escape.
test "runtime allocators: owned Zig backing stores are zeroed and released" {
    @import("../test.zig").ensureV8();
    var backing = std.heap.DebugAllocator(.{ .thread_safe = true, .enable_memory_limit = true }){};
    defer t.expect(backing.deinit() == .ok) catch @panic("backing-store leak");
    {
        var rt = try m.Runtime.initWithOptions(t.allocator, .{ .array_buffer_allocator = .{ .zig = backing.allocator() } });
        defer rt.deinit();
        const scope = try rt.createScope(.{});
        try check(scope, "globalThis.buffer = new ArrayBuffer(65536); const view = new Uint8Array(buffer); view.every(x => x === 0) && (view[3] = 42) === 42");
        try t.expect(backing.total_requested_bytes >= 65536);
        // Fail only backing-store allocation; runtime metadata uses t.allocator.
        backing.requested_memory_limit = backing.total_requested_bytes;
        var info: m.ErrorInfo = .{};
        defer info.deinit();
        try t.expectError(error.JavaScriptException, scope.eval("new ArrayBuffer(1024 * 1024)", "test:backing-oom", &info));
        try t.expect(info.exception != null);
        try check(scope, "new Uint8Array(buffer)[3] === 42");
    }
    try t.expectEqual(@as(usize, 0), backing.total_requested_bytes);
}

test "runtime allocators: borrowed adapter survives runtime with retained backing store" {
    @import("../test.zig").ensureV8();
    var backing = std.heap.DebugAllocator(.{ .thread_safe = true, .enable_memory_limit = true }){};
    defer t.expect(backing.deinit() == .ok) catch @panic("borrowed allocator leak");
    const aba = try v8.ArrayBuffer.Allocator.fromZig(backing.allocator());
    defer aba.deinit();
    const adapter_bytes = backing.total_requested_bytes;
    var store: v8.SharedBackingStore = undefined;
    var store_alive = false;
    defer if (store_alive) store.deinit();
    var bytes: []u8 = undefined;
    {
        var rt = try m.Runtime.initWithOptions(t.allocator, .{ .array_buffer_allocator = .{ .borrowed = aba } });
        defer rt.deinit();
        const scope = try rt.createScope(.{});
        rt.isolate.enter();
        defer rt.isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(rt.isolate);
        defer h_scope.deinit();
        const ctx = scope.context.deref();
        ctx.enter();
        defer ctx.exit();
        const buffer = v8.ArrayBuffer.newWithByteLength(rt.isolate, 256).?;
        try t.expectEqual(@as(usize, 0), @intFromPtr(buffer.data().?) % 16);
        bytes = @as([*]u8, @ptrCast(buffer.data().?))[0..256];
        const zeroes: [256]u8 = @splat(0);
        try t.expectEqualSlices(u8, &zeroes, bytes);
        bytes[0] = 42;
        store = buffer.getBackingStore();
        store_alive = true;
    }
    try t.expectEqual(@as(u8, 42), bytes[0]);
    try t.expectEqual(adapter_bytes + 256, backing.total_requested_bytes);
    store.deinit();
    store_alive = false;
    try t.expectEqual(adapter_bytes, backing.total_requested_bytes);
}

test "runtime allocators: mimalloc metadata and ArrayBuffer integration" {
    @import("../test.zig").ensureV8();
    var rt = try m.Runtime.initWithOptions(mimalloc.allocator, .{ .array_buffer_allocator = .{ .zig = mimalloc.allocator } });
    defer rt.deinit();
    const scope = try rt.createScope(.{});
    try check(scope, "const data = new Uint8Array(8192); data.every(x => x === 0) && (data[5] = 99) === 99 && new ArrayBuffer(0).byteLength === 0");
    try scope.module_map.update(.{ .module_id = "memory" }, .{ .source = "export const value = new Uint8Array(4096).every(x => x === 0)" }, null);
    try exposeModule(scope, "memory", "memory");
    try check(scope, "memory.value");
}

test "managed step 1: scopes, strict evaluation, persistent handles and context restoration" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const a = try rt.createScope(.{});
    const b = try rt.createScope(.{});
    try check(a, "globalThis.local = 1; local === 1");
    try check(b, "typeof local === 'undefined'");
    try t.expectError(error.JavaScriptException, a.eval("undeclared = 1", "test:strict", null));
    const retained = try a.eval("({ answer: 42 })", "test:retain", null);
    defer retained.deinit();
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    const ac = a.context.deref();
    ac.enter();
    defer ac.exit();
    try check(b, "true");
    try t.expect(rt.isolate.getCurrentContext().eq(ac));
    const bc = b.context.deref();
    try t.expect(!ac.getSecurityToken().?.strictEquals(bc.getSecurityToken().?));
    try t.expect(bc.getGlobal().set(bc, v8.String.initUtf8(rt.isolate, "foreign").name.primitive.value, ac.getGlobal().value).?);
    try t.expectError(error.JavaScriptException, b.eval("foreign.local", "test:foreign", null));
    const obj = retained.deref().toObject(ac).?;
    try t.expectEqual(@as(i32, 42), obj.get(ac, v8.String.initUtf8(rt.isolate, "answer").name.primitive.value).?.i32Value(ac).?);
}

fn sameRetainedValue(rt: *m.Runtime, a: v8.Global.Of(v8.Value), b: v8.Global.Of(v8.Value)) !void {
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    try t.expect(a.deref().strictEquals(b.deref()));
}

// Local V8 scopes are released before return; no resources escape.
test "error info: eval retains thrown identity, syntax errors and undefined" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const scope = try rt.createScope(.{});
    const marker = try scope.eval("globalThis.marker = {value: 42}; marker", "test:marker", null);
    defer marker.deinit();
    var error_info: m.ErrorInfo = .{};
    defer error_info.deinit();
    try t.expectError(error.JavaScriptException, scope.eval("throw marker", "test:throw", &error_info));
    try sameRetainedValue(&rt, error_info.exception.?, marker);
    const success = try scope.eval("42", "test:success", &error_info);
    defer success.deinit();
    try t.expect(error_info.exception == null);
    try t.expectError(error.JavaScriptException, scope.eval("throw undefined", "test:undefined", &error_info));
    const undefined_value = try scope.eval("undefined", "test:undefined-value", null);
    defer undefined_value.deinit();
    try sameRetainedValue(&rt, error_info.exception.?, undefined_value);
    try t.expectError(error.JavaScriptException, scope.eval("const =", "test:syntax", &error_info));
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    const ctx = scope.context.deref();
    ctx.enter();
    defer ctx.exit();
    try t.expect(error_info.exception.?.deref().isNativeError());
    try t.expect(ctx.getGlobal().set(ctx, v8.String.initUtf8(rt.isolate, "syntaxError").name.primitive.value, error_info.exception.?.deref()).?);
    try check(scope, "syntaxError.name === 'SyntaxError'");
}

test "error info: hardening and capability installation preserve caught errors" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const scope = try rt.createScope(.{});
    const proxy = try scope.eval("new Proxy({}, {})", "test:proxy", null);
    defer proxy.deinit();
    var error_info: m.ErrorInfo = .{};
    defer error_info.deinit();
    try t.expectError(error.UnsupportedExport, scope.harden(proxy, &error_info));
    try t.expect(error_info.exception != null);
    try t.expectError(error.UnsupportedExport, scope.installCapability("proxy", proxy, &error_info));
    try t.expect(error_info.exception != null);
    const record = try scope.eval("({value: 42})", "test:record", null);
    defer record.deinit();
    try scope.installCapability("record", record, &error_info);
    try t.expect(error_info.exception == null);
    try check(scope, "record.value === 42 && typeof proxy === 'undefined'");
}

test "error info: module-map compilation failures and promise rejections" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const scope = try rt.createScope(.{});
    const key: m.ModuleMapKey = .{ .module_id = "module" };
    var error_info: m.ErrorInfo = .{};
    defer error_info.deinit();
    try t.expectError(error.JavaScriptException, scope.updateImportCache(key, .{ .source = "export const =" }, &error_info));
    try t.expect(error_info.exception != null);
    var cached_error_info: m.ErrorInfo = .{};
    defer cached_error_info.deinit();
    try t.expectError(error.JavaScriptException, scope.module_map.get(key, &cached_error_info));
    try sameRetainedValue(&rt, error_info.exception.?, cached_error_info.exception.?);
    const rejected = try scope.importModule("module", &error_info);
    defer rejected.deinit();
    try t.expect(error_info.exception == null);
    try expectState(&rt, rejected, .Rejected);
    try scope.module_map.update(key, .{ .source = "export const value = 42" }, &error_info);
    try t.expect(error_info.exception == null);
    const recovered = try scope.importModuleWithAttributes("module", &.{}, &error_info);
    defer recovered.deinit();
    rt.pump();
    try expectState(&rt, recovered, .Fulfilled);
    try t.expect(error_info.exception == null);
    try t.expectError(error.JavaScriptException, scope.module_map.update(key, .{ .source = "export const =" }, &error_info));
    try t.expect(error_info.exception != null);
}

test "managed step 2: intrinsic inventory and code generation lockdown" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const scope = try rt.createScope(.{});
    const attacks = [_][]const u8{
        "Object.prototype.polluted = true",                                               "Array.prototype.push = () => 0",
        "Object.defineProperty(Object.prototype, Symbol.iterator, {value: 1})",           "Object.setPrototypeOf(Object.prototype, {})",
        "Object = function(){}",                                                          "Object.getPrototypeOf([][Symbol.iterator]()).next = () => 0",
        "Object.getPrototypeOf(Object.getPrototypeOf((function*(){})())).next = () => 0", "Object.getPrototypeOf(Object.getPrototypeOf((async function*(){})())).next = () => 0",
        "Function('return globalThis')()",                                                "eval('1')",
        "(async()=>{}).constructor('return 1')()",                                        "(function*(){}).constructor('yield 1')()",
        "(async function*(){}).constructor('yield 1')()",                                 "Date.prototype.setTime(0)",
    };
    for (attacks) |attack| try t.expectError(error.JavaScriptException, scope.eval(attack, "test:attack", null));
    try check(scope, "typeof WebAssembly === 'undefined' && typeof SharedArrayBuffer === 'undefined' && typeof Atomics === 'undefined'");
    try check(scope, "class C { #x = 1; inc() { return ++this.#x; } }; new C().inc() === 2 && [1,2].map(x=>x+1)[1] === 3");
    try check(scope, "new Date(0).setTime(1) === 1 && Object.isFrozen(Object.getPrototypeOf(async()=>{}))");
    try check(scope, "globalThis.done = false; Promise.resolve().then(()=>{done = true}); true");
    rt.pump();
    try check(scope, "done === true");
}

test "managed step 3: hardened sharing and private state" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const a = try rt.createScope(.{});
    const b = try rt.createScope(.{});
    const cap = try a.eval("new (class Counter { #n = 0; inc() { return ++this.#n; } })()", "test:counter", null);
    defer cap.deinit();
    try a.installCapability("counter", cap, null);
    try b.installCapability("counter", cap, null);
    try b.installCapability("sameCounter", cap, null);
    try check(b, "counter === sameCounter && counter.inc() === 1 && Reflect.ownKeys(counter).length === 0");
    try check(a, "counter.inc() === 2");
    try t.expectError(error.JavaScriptException, b.eval("counter.inc.call({})", "test:brand", null));
    try t.expectError(error.JavaScriptException, b.eval("Object.getPrototypeOf(counter).inc = () => 0", "test:prototype", null));
    try t.expectError(error.JavaScriptException, b.eval("counter = {}", "test:binding", null));
    const cycle = try a.eval("globalThis.accessed = 0; const graph = {get x(){accessed++; throw 1}}; graph.self = graph; graph", "test:cycle", null);
    defer cycle.deinit();
    try a.harden(cycle, null);
    try check(a, "accessed === 0 && Object.isFrozen(graph)");
    const unsupported = [_][]const u8{ "new Map()", "new Date()", "new Uint8Array(1)", "Promise.resolve(1)", "new WeakRef({})", "[][Symbol.iterator]()", "globalThis", "new Proxy({}, {ownKeys(){throw 1}})" };
    for (unsupported) |source| {
        const value = try a.eval(source, "test:unsupported", null);
        defer value.deinit();
        try t.expectError(error.UnsupportedExport, a.harden(value, null));
    }
}

const Memory = struct {
    loads: usize = 0,
    pub fn resolve(_: ?*anyopaque, request: m.ResolveRequest) ![]const u8 {
        return request.allocator.dupe(u8, request.specifier);
    }
    pub fn load(data: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
        if (request.import_attributes.len != 0) return error.UnsupportedImportAttributes;
        const scope = request.scope_id;
        const id = request.module_id;
        const self: *Memory = @ptrCast(@alignCast(data.?));
        self.loads += 1;
        if (std.mem.eql(u8, id, "dep")) return .{ .source = if (scope == 0) "export const value = 1" else "export const value = 2" };
        if (std.mem.eql(u8, id, "main")) return .{ .source = "import {value} from 'dep'; export const answer = value; export const origin = import.meta.url; export async function later(){return (await import('dep')).value};" };
        if (std.mem.eql(u8, id, "cycle-a")) return .{ .source = "import {b} from 'cycle-b'; export const a = 3; export function read(){ return b() }" };
        if (std.mem.eql(u8, id, "cycle-b")) return .{ .source = "import {a} from 'cycle-a'; export function b(){return a}" };
        if (std.mem.eql(u8, id, "await")) return .{ .source = "export const value = await Promise.resolve(42)" };
        if (std.mem.eql(u8, id, "dynamic")) return .{ .source = "export const value = (await import('dep')).value" };
        if (std.mem.eql(u8, id, "syntax")) return .{ .source = "export const =" };
        if (std.mem.eql(u8, id, "throw")) return .{ .source = "throw new Error('boom')" };
        if (std.mem.eql(u8, id, "missing-export")) return .{ .source = "import {nope} from 'dep'; export {nope}" };
        if (std.mem.eql(u8, id, "attributes")) return .{ .source = "import x from 'dep' with {type:'json'}" };
        return error.NotFound;
    }
    fn options(self: *Memory) m.Scope.Options {
        return .{ .resolver = .{ .resolve = resolve }, .loader = .{ .data = self, .load = load } };
    }
};

fn exposeModule(scope: *m.Scope, id: []const u8, name: []const u8) !void {
    const promise = try scope.importModule(id, null);
    defer promise.deinit();
    scope.runtime.pump();
    const iso = scope.runtime.isolate;
    iso.enter();
    defer iso.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(iso);
    defer h_scope.deinit();
    const p = promise.deref();
    try t.expectEqual(v8.Promise.PromiseState.Fulfilled, p.state());
    const ctx = scope.context.deref();
    ctx.enter();
    defer ctx.exit();
    // Test-only raw namespace installation. Public capabilities reject namespaces.
    try t.expect(ctx.getGlobal().set(ctx, v8.String.initUtf8(iso, name).name.primitive.value, p.result()).?);
}

// Local V8 scopes are released before return; no resources escape.
test "managed step 4: native ESM graphs, cycles, TLA and defining scope" {
    @import("../test.zig").ensureV8();
    var memory: Memory = .{};
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const a = try rt.createScope(memory.options());
    const b = try rt.createScope(memory.options());
    try exposeModule(a, "main", "main");
    try exposeModule(b, "main", "main");
    try check(a, "main.answer === 1 && main.origin === 'main'");
    try check(b, "main.answer === 2");
    const loads = memory.loads;
    try exposeModule(a, "main", "again");
    try check(a, "main === again");
    try t.expectEqual(loads, memory.loads);
    try exposeModule(a, "cycle-a", "cycle");
    try check(a, "cycle.read() === 3");
    try exposeModule(a, "await", "awaited");
    try check(a, "awaited.value === 42");
    try exposeModule(a, "dynamic", "dynamic");
    try check(a, "dynamic.value === 1");
    const later = try a.eval("main.later", "test:later", null);
    defer later.deinit();
    try b.installCapability("fromA", later, null);
    try check(b, "globalThis.answer = 0; fromA().then(value => {answer = value}); true");
    rt.pump();
    try check(b, "answer === 1");
    for ([_][]const u8{ "syntax", "throw", "missing-export", "attributes", "absent" }) |id| {
        const promise = try a.importModule(id, null);
        defer promise.deinit();
        rt.pump();
        rt.isolate.enter();
        defer rt.isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(rt.isolate);
        defer h_scope.deinit();
        try t.expectEqual(v8.Promise.PromiseState.Rejected, promise.deref().state());
    }
}

const Deferred = struct {
    tokens: [8]m.LoadToken = @splat(0),
    count: usize = 0,
    cancelled: usize = 0,
    fn load(data: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
        const self: *Deferred = @ptrCast(@alignCast(data.?));
        self.tokens[self.count] = request.token;
        self.count += 1;
        return .pending;
    }
    fn cancel(data: ?*anyopaque, _: m.LoadToken) void {
        const self: *Deferred = @ptrCast(@alignCast(data.?));
        self.cancelled += 1;
    }
    fn options(self: *Deferred) m.Scope.Options {
        return .{ .resolver = .{ .resolve = Memory.resolve }, .loader = .{ .data = self, .load = load, .cancel = cancel } };
    }
};
fn expectState(rt: *m.Runtime, promise: v8.Global.Of(v8.Promise), expected: v8.Promise.PromiseState) !void {
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    try t.expectEqual(expected, promise.deref().state());
}

test "managed step 5: deferred backend, deduplication, cycles and stale tokens" {
    @import("../test.zig").ensureV8();
    var backend: Deferred = .{};
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const scope = try rt.createScope(backend.options());
    const first = try scope.importModule("root", null);
    defer first.deinit();
    const again = try scope.importModule("root", null);
    defer again.deinit();
    try t.expectEqual(@as(usize, 1), backend.count);
    try expectState(&rt, first, .Pending);
    try rt.completeLoad(backend.tokens[0], .{ .content = .{ .source = "import {a} from 'a'; import {b} from 'b'; export const value = await Promise.resolve(a() + b); export const root = 7;" } });
    try t.expectEqual(@as(usize, 3), backend.count);
    try rt.completeLoad(backend.tokens[2], .{ .content = .{ .source = "export const b = 2" } });
    rt.pump();
    try expectState(&rt, first, .Pending);
    try rt.completeLoad(backend.tokens[1], .{ .content = .{ .source = "import {root} from 'root'; export function a(){return root}" } });
    rt.pump();
    // Calling a() before root initializes throws: cycle loading succeeds, evaluation correctly rejects.
    try expectState(&rt, first, .Rejected);
    try expectState(&rt, again, .Rejected);
    try t.expectError(error.StaleLoadToken, rt.completeLoad(backend.tokens[1], .{ .failure = error.NotFound }));
    try t.expectError(error.StaleLoadToken, rt.completeLoad(999, .{ .failure = error.NotFound }));
    const failed = try scope.importModule("failed", null);
    defer failed.deinit();
    try rt.completeLoad(backend.tokens[3], .{ .failure = error.NotFound });
    rt.pump();
    try expectState(&rt, failed, .Rejected);
    const success = try scope.importModule("success", null);
    defer success.deinit();
    try rt.completeLoad(backend.tokens[4], .{ .content = .{ .source = "export const value = await Promise.resolve(42)" } });
    rt.pump();
    try expectState(&rt, success, .Fulfilled);
}

test "managed step 5: teardown cancels pending requests" {
    @import("../test.zig").ensureV8();
    var backend: Deferred = .{};
    var rt = m.Runtime.init(t.allocator);
    const scope = try rt.createScope(backend.options());
    const promise = try scope.importModule("pending", null);
    promise.deinit();
    rt.deinit();
    try t.expectEqual(@as(usize, 1), backend.cancelled);
}

test "managed steps 4-5: synthetic capability exports and asynchronous successful cycles" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const owner = try rt.createScope(.{});
    const value = try owner.eval("({answer:42})", "test:export", null);
    defer value.deinit();
    var exports = [_]m.Export{.{ .name = "cap", .value = value }};
    const Synthetic = struct {
        fn load(data: ?*anyopaque, _: m.LoadRequest) !m.LoadResult {
            const items: *[1]m.Export = @ptrCast(@alignCast(data.?));
            return .{ .exports = items };
        }
    };
    const synthetic = try rt.createScope(.{ .resolver = .{ .resolve = Memory.resolve }, .loader = .{ .data = &exports, .load = Synthetic.load } });
    try exposeModule(synthetic, "capability", "caps");
    try check(synthetic, "caps.cap.answer === 42 && Object.isFrozen(caps.cap)");
    var backend: Deferred = .{};
    const scope = try rt.createScope(backend.options());
    const promise = try scope.importModule("root", null);
    defer promise.deinit();
    try rt.completeLoad(backend.tokens[0], .{ .content = .{ .source = "import {read} from 'child'; export const n = 4; export const value = () => read();" } });
    try rt.completeLoad(backend.tokens[1], .{ .content = .{ .source = "import {n} from 'root'; export function read(){return n}" } });
    rt.pump();
    try expectState(&rt, promise, .Fulfilled);
}

test "managed step 6: immutable maps, scope precedence, virtual URLs and blocked paths" {
    const json =
        \\{"imports":{"lib":"./lib.js","pkg/":"./packages/","pkg/deep/":"./deep/","blocked":null,"./alias.js":"./real.js"},
        \\"scopes":{"./plugins/":{"lib":"./plugin.js","blocked":null},"./plugins/a/":{"extra":"./extra.js"},"./exact.js":{"lib":"./exact-lib.js"}}}
    ;
    var map = try m.ImportMap.parseJson(t.allocator, json, .{ .base_url = "app:/root/map.json", .urls = m.virtual_urls });
    defer map.deinit();
    try expectMapResolution(&map, "lib", "app:/root/main.js", "app:/root/lib.js");
    try expectMapResolution(&map, "lib", "app:/root/plugins/a/main.js", "app:/root/plugin.js");
    try expectMapResolution(&map, "extra", "app:/root/plugins/a/main.js", "app:/root/extra.js");
    try expectMapResolution(&map, "lib", "app:/root/exact.js", "app:/root/exact-lib.js");
    try expectMapResolution(&map, "lib", "app:/root/exact.js/child", "app:/root/lib.js");
    try expectMapResolution(&map, "pkg/deep/a.js", "", "app:/root/deep/a.js");
    try expectMapResolution(&map, "pkg/a.js", "", "app:/root/packages/a.js");
    try expectMapResolution(&map, "./alias.js", "app:/root/main.js", "app:/root/real.js");
    try expectMapResolution(&map, "../other.js", "app:/root/plugins/main.js", "app:/root/other.js");
    try t.expectError(error.BlockedImport, map.resolve(t.allocator, "blocked", ""));
    try t.expectError(error.ImportMapBacktracking, map.resolve(t.allocator, "pkg/../escape.js", ""));
    try t.expectError(error.ImportMapBacktracking, map.resolve(t.allocator, "pkg/%2e%2e/escape.js", ""));
    try t.expectError(error.UnmappedSpecifier, map.resolve(t.allocator, "missing", ""));
    try expectMapResolution(&map, "app:/a%2eb.js?q=%2e%2f", "", "app:/a%2eb.js?q=%2e%2f");
    for ([_][]const u8{ "[]", "{\"imports\": []}", "{\"imports\": {\"x\":\"bare\"}}", "{\"imports\": {\"x/\":\"./file.js\"}}" }) |invalid| {
        if (m.ImportMap.parseJson(t.allocator, invalid, .{ .base_url = "app:/map.json", .urls = m.virtual_urls })) |good| {
            var unexpected = good;
            unexpected.deinit();
            return error.ExpectedInvalidMap;
        } else |_| {}
    }
}

test "typed import maps: caller construction and reuse outlive caller map" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    {
        var map = try m.ImportMap.init(t.allocator, .{
            .base_url = "app:/map.json",
            .urls = m.virtual_urls,
            .imports = &.{ .{ .key = "demo", .target = "./one.js" }, .{ .key = "blocked", .target = null } },
            .scopes = &.{.{ .prefix = "./nested/", .mappings = &.{.{ .key = "demo", .target = "./two.js" }} }},
        });
        defer map.deinit();
        try expectMapResolution(&map, "demo", "app:/nested/main.js", "app:/two.js");
        try t.expectError(error.BlockedImport, map.resolve(t.allocator, "blocked", ""));
        _ = try rt.createScope(.{ .import_map = &map });
        _ = try rt.createScope(.{ .import_map = &map });
    }
    const a = rt.scopes.items[0];
    const b = rt.scopes.items[1];
    try t.expect(a.import_map.? != b.import_map.?);
    try a.module_map.update(.{ .module_id = "app:/one.js" }, .{ .source = "export const value = 1" }, null);
    try b.module_map.update(.{ .module_id = "app:/one.js" }, .{ .source = "export const value = 2" }, null);
    try exposeModule(a, "demo", "module");
    try exposeModule(b, "demo", "module");
    try check(a, "module.value === 1");
    try check(b, "module.value === 2");
}

test "managed module maps: independent mappings without a resolver or loader" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const a = try rt.createScope(.{});
    const b = try rt.createScope(.{});
    const key: m.ModuleMapKey = .{ .module_id = "same" };
    try a.module_map.update(key, .{ .source = "export const value = 1" }, null);
    try b.module_map.update(key, .{ .source = "export const value = 2" }, null);
    const retained = (try a.module_map.get(key, null)).?;
    defer retained.deinit();
    try exposeModule(a, "same", "first");
    try exposeModule(a, "same", "again");
    try exposeModule(b, "same", "other");
    try check(a, "first === again && first.value === 1");
    try check(b, "other.value === 2");
    try a.module_map.update(key, .{ .source = "export const value = 3" }, null);
    try exposeModule(a, "same", "updated");
    try check(a, "updated !== first && updated.value === 3 && first.value === 1");
    try t.expectEqual(@as(usize, 1), try a.module_map.delete(key));
    try t.expect(try a.module_map.get(key, null) == null);
    try check(b, "other.value === 2");
    // Compatibility operations address the exact same module map.
    try b.updateImportCache(key, .{ .source = "export const value = 4" }, null);
    try exposeModule(b, "same", "replacement");
    try check(b, "replacement.value === 4");
    try t.expectEqual(@as(usize, 1), try b.module_map.clear());
    try t.expect(try b.module_map.get(key, null) == null);
}

// Local V8 scopes are released before return; no resources escape.
test "managed module maps: lookup normalizes attributes and retains native identity" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const scope = try rt.createScope(.{});
    const attrs = [_]m.ImportAttribute{ .{ .key = "type", .value = "custom" }, .{ .key = "mode", .value = "one" } };
    const key: m.ModuleMapKey = .{ .module_id = "payload", .import_attributes = &attrs };
    const reordered: m.ModuleMapKey = .{ .module_id = "payload", .import_attributes = &.{ attrs[1], attrs[0] } };
    try scope.module_map.update(key, .{ .source = "export const value = 1" }, null);
    try scope.module_map.update(.{ .module_id = "payload" }, .{ .source = "export const value = 2" }, null);
    const first = (try scope.module_map.get(key, null)).?;
    defer first.deinit();
    const again = (try scope.module_map.get(reordered, null)).?;
    defer again.deinit();
    const plain = (try scope.module_map.get(.{ .module_id = "payload" }, null)).?;
    defer plain.deinit();
    try t.expect(try scope.module_map.get(.{ .module_id = "payload", .import_attributes = &.{.{ .key = "type", .value = "other" }} }, null) == null);
    try t.expectEqual(@as(usize, 1), try scope.module_map.delete(reordered));
    try t.expect(try scope.module_map.get(key, null) == null);
    try t.expectEqual(@as(usize, 1), try scope.module_map.clear());
    // Handles returned by get survive both the local handle scope and map eviction.
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    try t.expect(first.deref().data.eq(again.deref().data));
    try t.expect(!first.deref().data.eq(plain.deref().data));
    try t.expect(first.deref().isSourceTextModule());
}

test "managed module maps: alias imports share a loaded module and lookup never loads" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const Backend = struct {
        loads: usize = 0,
        fn resolve(_: ?*anyopaque, request: m.ResolveRequest) ![]const u8 {
            return request.allocator.dupe(u8, "canonical");
        }
        fn load(data: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            try t.expectEqualStrings("canonical", request.module_id);
            self.loads += 1;
            return .{ .source = "export const value = 1" };
        }
    };
    var backend: Backend = .{};
    const scope = try rt.createScope(.{ .resolver = .{ .resolve = Backend.resolve }, .loader = .{ .data = &backend, .load = Backend.load } });
    try t.expect(try scope.module_map.get(.{ .module_id = "canonical" }, null) == null);
    try t.expectEqual(@as(usize, 0), backend.loads);
    try exposeModule(scope, "alias-a", "first");
    try exposeModule(scope, "alias-b", "second");
    try check(scope, "first === second");
    try t.expectEqual(@as(usize, 1), backend.loads);
    try t.expect(try scope.module_map.get(.{ .module_id = "alias-a" }, null) == null);
    try t.expectEqual(@as(usize, 0), try scope.module_map.delete(.{ .module_id = "alias-a" }));
    try scope.module_map.update(.{ .module_id = "canonical" }, .{ .source = "export const value = 9" }, null);
    try exposeModule(scope, "alias-b", "updated");
    try check(scope, "updated.value === 9 && first.value === 1 && updated !== first");
    try t.expectEqual(@as(usize, 1), backend.loads);
    try t.expectEqual(@as(usize, 1), try scope.module_map.delete(.{ .module_id = "canonical" }));
    try exposeModule(scope, "alias-a", "reloaded");
    try check(scope, "reloaded.value === 1 && reloaded !== first");
    try t.expectEqual(@as(usize, 2), backend.loads);
}

test "managed module maps: pending and failed lookups recover through replacement" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    var backend: Deferred = .{};
    const scope = try rt.createScope(backend.options());
    const key: m.ModuleMapKey = .{ .module_id = "pending" };
    const pending = try scope.importModule("pending", null);
    defer pending.deinit();
    try t.expect(try scope.module_map.get(key, null) == null);
    try t.expectEqual(@as(usize, 1), backend.count);
    try rt.completeLoad(backend.tokens[0], .{ .failure = error.NotFound });
    rt.pump();
    try expectState(&rt, pending, .Rejected);
    try t.expectError(error.JavaScriptException, scope.module_map.get(key, null));
    try scope.module_map.update(key, .{ .source = "export const value = 42" }, null);
    const recovered = (try scope.module_map.get(key, null)).?;
    defer recovered.deinit();
    try exposeModule(scope, "pending", "recovered");
    try check(scope, "recovered.value === 42");
    try t.expectEqual(@as(usize, 1), backend.count);
    try t.expectError(error.JavaScriptException, scope.module_map.update(key, .{ .source = "export const =" }, null));
    try t.expectError(error.JavaScriptException, scope.module_map.get(key, null));
    try t.expectEqual(@as(usize, 1), try scope.module_map.delete(key));
    try t.expect(try scope.module_map.get(key, null) == null);
    try check(scope, "recovered.value === 42");
}

test "managed module maps: import rewriting precedes static and dynamic lookup" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    var import_map_1 = try m.ImportMap.parseJson(t.allocator, "{\"imports\":{\"root\":\"app:/main.js\",\"dep\":\"app:/one.js\"}}", .{ .base_url = "app:/map.json", .urls = m.virtual_urls });
    defer import_map_1.deinit();
    const a = try rt.createScope(.{ .import_map = &import_map_1 });
    var import_map_2 = try m.ImportMap.parseJson(t.allocator, "{\"imports\":{\"root\":\"app:/main.js\",\"dep\":\"app:/two.js\"}}", .{ .base_url = "app:/map.json", .urls = m.virtual_urls });
    defer import_map_2.deinit();
    const b = try rt.createScope(.{ .import_map = &import_map_2 });
    try a.module_map.update(.{ .module_id = "app:/one.js" }, .{ .source = "export const value = 1" }, null);
    try b.module_map.update(.{ .module_id = "app:/two.js" }, .{ .source = "export const value = 2" }, null);
    const source = "import {value} from 'dep'; export {value}; export async function later(){return (await import('dep')).value}";
    for ([_]*m.Scope{ a, b }) |scope| {
        try scope.module_map.update(.{ .module_id = "app:/main.js" }, .{ .source = source }, null);
        try t.expect(try scope.module_map.get(.{ .module_id = "dep" }, null) == null);
        const module = (try scope.module_map.get(.{ .module_id = "app:/main.js" }, null)).?;
        module.deinit();
        try exposeModule(scope, "root", "main");
        try check(scope, "globalThis.laterValue = 0; main.later().then(v => { laterValue = v }); true");
    }
    rt.pump();
    try check(a, "main.value === 1 && laterValue === 1");
    try check(b, "main.value === 2 && laterValue === 2");
    try t.expectEqual(@as(usize, 2), try a.module_map.delete(.{ .module_id = "app:/one.js" }));
    try t.expect(try a.module_map.get(.{ .module_id = "app:/main.js" }, null) == null);
    const unaffected = (try b.module_map.get(.{ .module_id = "app:/main.js" }, null)).?;
    unaffected.deinit();
    try check(a, "main.value === 1");
}

test "managed step 6: different import maps with the same virtual backend" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const Backend = struct {
        fn load(_: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
            if (std.mem.eql(u8, request.module_id, "app:/one.js")) return .{ .source = "export const value = 1" };
            if (std.mem.eql(u8, request.module_id, "app:/two.js")) return .{ .source = "export const value = 2" };
            return error.NotFound;
        }
    };
    var import_map_3 = try m.ImportMap.parseJson(t.allocator, "{\"imports\":{\"same\":\"./one.js\"}}", .{ .base_url = "app:/map.json", .urls = m.virtual_urls });
    defer import_map_3.deinit();
    const a = try rt.createScope(.{ .import_map = &import_map_3, .loader = .{ .load = Backend.load } });
    var import_map_4 = try m.ImportMap.parseJson(t.allocator, "{\"imports\":{\"same\":\"./two.js\"}}", .{ .base_url = "app:/map.json", .urls = m.virtual_urls });
    defer import_map_4.deinit();
    const b = try rt.createScope(.{ .import_map = &import_map_4, .loader = .{ .load = Backend.load } });
    try exposeModule(a, "same", "module");
    try exposeModule(b, "same", "module");
    try check(a, "module.value === 1");
    try check(b, "module.value === 2");
}

const NativeCounter = struct {
    key: v8.Global.Of(v8.Private),
    fn increment(info: v8.FunctionCallbackInfo) callconv(.c) void {
        const self: *NativeCounter = @ptrCast(@alignCast(v8.External.from_opaque(info.data().?.handle).?.pointer()));
        const iso = info.isolate();
        const ctx = iso.getCurrentContext();
        const receiver = info.this();
        if (!(receiver.hasPrivate(ctx, self.key.deref()) orelse false) or info.length() != 1 or !info.get_arg(0).isInt32()) {
            _ = iso.throwException(v8.Exception.typeError(v8.String.initUtf8(iso, "Invalid counter receiver or argument")).?);
            return;
        }
        const prior = receiver.getPrivate(ctx, self.key.deref()).?.i32Value(ctx).?;
        const delta = info.get_arg(0).i32Value(ctx).?;
        const next = std.math.add(i32, prior, delta) catch {
            _ = iso.throwException(v8.Exception.rangeError(v8.String.initUtf8(iso, "Counter overflow")).?);
            return;
        };
        _ = receiver.setPrivate(ctx, self.key.deref(), v8.Number.initInt(iso, next).numeric.primitive.value);
        var result = info.retval();
        result.setInt32(next);
    }
};

// Local V8 scopes are released before return; no resources escape.
test "managed step 7: native private capabilities validate receivers without coercion" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const a = try rt.createScope(.{});
    const b = try rt.createScope(.{});
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    const ctx = a.context.deref();
    ctx.enter();
    defer ctx.exit();
    var native: NativeCounter = .{ .key = .new(rt.isolate, v8.Private.init(rt.isolate, null)) };
    defer native.key.deinit();
    const object = v8.Object.init(rt.isolate);
    try t.expect(object.setPrivate(ctx, native.key.deref(), v8.Number.initInt(rt.isolate, 0).numeric.primitive.value).?);
    const function = v8.Function.init(ctx, NativeCounter.increment, v8.External.init(rt.isolate, &native).value.data, 1, .Throw, .HasSideEffect);
    try t.expect(object.createDataProperty(ctx, v8.String.initUtf8(rt.isolate, "inc").name, function.object.value).?);
    const cap = v8.Global.Of(v8.Value).new(rt.isolate, object.value);
    defer cap.deinit();
    try b.installCapability("native", cap, null);
    try check(b, "native.inc(2) === 2 && Reflect.ownKeys(native).length === 1");
    try t.expectError(error.JavaScriptException, b.eval("native.inc.call({}, 1)", "test:forged", null));
    try check(b, "globalThis.coerced = false; try {native.inc({valueOf(){coerced = true; throw 1}})} catch {} !coerced");
    try t.expectError(error.JavaScriptException, b.eval("new native.inc(1)", "test:constructor", null));
    try check(b, "native.inc(3) === 5");
}

test "managed step 7: cross-scope exotic rejection, callbacks and failures" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const a = try rt.createScope(.{});
    const b = try rt.createScope(.{});
    for ([_][]const u8{ "new WeakRef({})", "new FinalizationRegistry(()=>{})", "[][Symbol.iterator]()", "new Proxy({}, {ownKeys(){throw 1}})" }) |source| {
        const value = try a.eval(source, "test:foreign-exotic", null);
        defer value.deinit();
        try t.expectError(error.UnsupportedExport, b.installCapability("bad", value, null));
    }
    const fn_ = try a.eval("(callback => callback(Object.freeze({value: 42})))", "test:callback", null);
    defer fn_.deinit();
    try b.installCapability("call", fn_, null);
    try check(b, "call(x => Object.isFrozen(x) && x.value === 42)");
    try check(b, "try {call(() => {throw 17})} catch (e) {globalThis.thrown = e} thrown === 17");
    const promised = try a.eval("(() => Promise.resolve(Object.freeze({value:42})))", "test:promise", null);
    defer promised.deinit();
    try b.installCapability("later", promised, null);
    try check(b, "globalThis.answer = 0; later().then(x=>{answer=x.value}); true");
    rt.pump();
    try check(b, "answer === 42");
    try t.expectError(error.InvalidImportMap, m.ImportMap.parseJson(t.allocator, "[]", .{ .base_url = "app:/map", .urls = m.virtual_urls }));
    try t.expectEqual(@as(usize, 2), rt.scopes.items.len);
    const valid = try rt.createScope(.{});
    try check(valid, "true");
}

const AttributeBackend = struct {
    payload_loads: usize = 0,
    checked_contexts: usize = 0,
    custom_error: ?v8.Global.Of(v8.Value) = null,

    fn resolve(_: ?*anyopaque, request: m.ResolveRequest) !m.ModuleId {
        try t.expect(request.context.eq(v8.Isolate.getCurrent().getCurrentContext()));
        if (std.mem.eql(u8, request.specifier, "resolve-error")) {
            _ = v8.Isolate.getCurrent().throwException(v8.Exception.typeError(v8.String.initUtf8(v8.Isolate.getCurrent(), "custom resolver error")).?);
            return error.ResolverDenied;
        }
        return request.allocator.dupe(u8, request.specifier);
    }
    fn load(data: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
        const self: *AttributeBackend = @ptrCast(@alignCast(data.?));
        const iso = v8.Isolate.getCurrent();
        try t.expect(request.context.eq(iso.getCurrentContext()));
        self.checked_contexts += 1;
        if (std.mem.eql(u8, request.module_id, "static-denied")) return .{ .source = "import 'denied';" };
        if (std.mem.eql(u8, request.module_id, "main")) return .{ .source =
        \\import {value as one} from 'payload' with {mode:'one',type:'custom'};
        \\import {value as two} from 'payload' with {type:'custom',mode:'two'};
        \\export const values = [one,two];
        };
        if (std.mem.eql(u8, request.module_id, "payload")) {
            self.payload_loads += 1;
            try t.expectEqual(@as(usize, 2), request.import_attributes.len);
            try t.expectEqualStrings("mode", request.import_attributes[0].key);
            try t.expectEqualStrings("type", request.import_attributes[1].key);
            try t.expectEqualStrings("custom", request.import_attributes[1].value);
            return .{ .source = if (std.mem.eql(u8, request.import_attributes[0].value, "one")) "export const value = 1" else "export const value = 2" };
        }
        if (std.mem.eql(u8, request.module_id, "denied") or std.mem.eql(u8, request.module_id, "thrown")) {
            const exception = v8.Exception.typeError(v8.String.initUtf8(iso, "custom loader error")).?;
            try t.expect(exception.toObject(request.context).?.createDataProperty(request.context, v8.String.initUtf8(iso, "code").name, v8.String.initUtf8(iso, "DENIED").name.primitive.value).?);
            if (self.custom_error) |prior| prior.deinit();
            self.custom_error = .new(iso, exception);
            if (std.mem.eql(u8, request.module_id, "thrown")) {
                _ = iso.throwException(exception);
                return error.LoaderDenied;
            }
            return .{ .exception = exception };
        }
        if (std.mem.eql(u8, request.module_id, "strict")) return .{ .source =
        \\export const strict = (function(){return this})() === undefined;
        \\export let denied = false;
        \\try { implicitModuleGlobal = 1 } catch (e) { denied = e instanceof ReferenceError }
        };
        return error.NotFound;
    }
    fn options(self: *AttributeBackend) m.Scope.Options {
        return .{ .resolver = .{ .resolve = resolve }, .loader = .{ .data = self, .load = load } };
    }
};

test "loader receives context and attributes for static, dynamic and host imports" {
    @import("../test.zig").ensureV8();
    var backend: AttributeBackend = .{};
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const scope = try rt.createScope(backend.options());
    try exposeModule(scope, "main", "module");
    try check(scope, "module.values[0] === 1 && module.values[1] === 2");
    try t.expectEqual(@as(usize, 2), backend.payload_loads);
    try check(scope, "globalThis.dynamicValue = 0; import('payload', {with:{type:'custom',mode:'one'}}).then(m=>{dynamicValue=m.value}); true");
    rt.pump();
    try check(scope, "dynamicValue === 1");
    const first = try scope.importModuleWithAttributes("payload", &.{ .{ .key = "type", .value = "custom" }, .{ .key = "mode", .value = "one" } }, null);
    defer first.deinit();
    try expectState(&rt, first, .Fulfilled);
    try t.expectEqual(@as(usize, 2), backend.payload_loads);
    try check(scope, "globalThis.dynamicTwo = 0; import('payload', {with:{type:'custom',mode:'new'}}).then(m=>{dynamicTwo=m.value}); true");
    rt.pump();
    try check(scope, "dynamicTwo === 2");
    try t.expectEqual(@as(usize, 3), backend.payload_loads);
    const duplicate = try scope.importModuleWithAttributes("payload", &.{ .{ .key = "type", .value = "one" }, .{ .key = "type", .value = "two" } }, null);
    defer duplicate.deinit();
    try expectState(&rt, duplicate, .Rejected);
    try t.expectEqual(@as(usize, 3), backend.payload_loads);
}

// Local V8 scopes are released before return; no resources escape.
test "custom loader and resolver exceptions preserve JavaScript errors" {
    @import("../test.zig").ensureV8();
    var backend: AttributeBackend = .{};
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    defer if (backend.custom_error) |exception| exception.deinit();
    const scope = try rt.createScope(backend.options());
    for ([_][]const u8{ "denied", "static-denied", "thrown" }) |id| {
        const promise = try scope.importModule(id, null);
        defer promise.deinit();
        try expectState(&rt, promise, .Rejected);
        rt.isolate.enter();
        defer rt.isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(rt.isolate);
        defer h_scope.deinit();
        try t.expect(promise.deref().result().strictEquals(backend.custom_error.?.deref()));
    }
    try check(scope, "globalThis.loaderError = false; import('denied').catch(e=>{loaderError = e instanceof TypeError && e.code === 'DENIED'}); true");
    rt.pump();
    try check(scope, "loaderError");
    try check(scope, "globalThis.resolverError = false; import('resolve-error').catch(e=>{resolverError = e instanceof TypeError && e.message === 'custom resolver error'}); true");
    rt.pump();
    try check(scope, "resolverError");
}

// Local V8 scopes are released before return; no resources escape.
test "pending loads preserve attributes and accept custom async exceptions" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const Backend = struct {
        token: m.LoadToken = 0,
        attributes: []const m.ImportAttribute = &.{},
        fn load(data: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            self.token = request.token;
            self.attributes = request.import_attributes;
            try t.expect(request.context.eq(v8.Isolate.getCurrent().getCurrentContext()));
            return .pending;
        }
    };
    var backend: Backend = .{};
    const scope = try rt.createScope(.{ .resolver = .{ .resolve = Memory.resolve }, .loader = .{ .data = &backend, .load = Backend.load } });
    var attribute_value = [_]u8{ 'j', 's', 'o', 'n' };
    const promise = try scope.importModuleWithAttributes("pending", &.{.{ .key = "type", .value = &attribute_value }}, null);
    defer promise.deinit();
    @memset(&attribute_value, 'x');
    try t.expectEqualStrings("json", backend.attributes[0].value);
    const exception = try scope.eval("Object.assign(new TypeError('async denial'),{code:'ASYNC'})", "test:async-error", null);
    defer exception.deinit();
    try rt.completeLoad(backend.token, .{ .exception = exception });
    rt.pump();
    try expectState(&rt, promise, .Rejected);
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    try t.expect(promise.deref().result().strictEquals(exception.deref()));
}

// Local V8 scopes are released before return; no resources escape.
test "strict mode is mandatory by default for scripts, hashbangs and ESM" {
    @import("../test.zig").ensureV8();
    var backend: AttributeBackend = .{};
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const scope = try rt.createScope(backend.options());
    try check(scope, "(function(){return this})() === undefined");
    try check(scope, "#!/usr/bin/env js\n(function(){return this})() === undefined");
    for ([_][]const u8{
        "implicitGlobal = 1",         "with ({}) {}",                                  "function duplicate(a,a){}", "010",
        "Object.freeze({a:1}).a = 2", "#!/usr/bin/env js\nimplicitHashbangGlobal = 1",
    }) |source| try t.expectError(error.JavaScriptException, scope.eval(source, "test:strict", null));
    try exposeModule(scope, "strict", "strictModule");
    try check(scope, "strictModule.strict && strictModule.denied && typeof implicitModuleGlobal === 'undefined'");
    const located = try scope.eval("\n(function located(){})", "test:unchanged-source", null);
    defer located.deinit();
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    try t.expectEqual(@as(c_int, 1), v8.Function.from_opaque(located.deref().data.handle).?.getScriptLineNumber());
}

const CacheBackend = struct {
    version: u8 = 1,
    loads: usize = 0,
    fn load(data: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
        const self: *CacheBackend = @ptrCast(@alignCast(data.?));
        self.loads += 1;
        if (std.mem.eql(u8, request.module_id, "dep")) return .{ .source = if (self.version == 1) "export const value = 1" else "export const value = 2" };
        if (std.mem.eql(u8, request.module_id, "main")) return .{ .source = "import {value} from 'dep'; export {value}; export function origin(){return import.meta.url}; export async function later(){return (await import('dep')).value}" };
        return error.NotFound;
    }
    fn options(self: *CacheBackend) m.Scope.Options {
        return .{ .resolver = .{ .resolve = Memory.resolve }, .loader = .{ .data = self, .load = load } };
    }
};

test "cache delete and update invalidate dependents while preserving old namespaces" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    var backend: CacheBackend = .{};
    const a = try rt.createScope(backend.options());
    const b = try rt.createScope(backend.options());
    try exposeModule(a, "main", "old");
    try exposeModule(b, "main", "other");
    backend.version = 2;
    try t.expectEqual(@as(usize, 2), try a.deleteImportCache(.{ .module_id = "dep" }));
    try t.expectEqual(@as(usize, 0), try a.deleteImportCache(.{ .module_id = "dep" }));
    try exposeModule(a, "main", "fresh");
    try check(a, "old.value === 1 && fresh.value === 2 && old !== fresh && old.origin() === 'main'");
    try check(b, "other.value === 1");
    const loads = backend.loads;
    try a.updateImportCache(.{ .module_id = "dep" }, .{ .source = "export const value = 99" }, null);
    try exposeModule(a, "main", "updated");
    try check(a, "old.value === 1 && fresh.value === 2 && updated.value === 99");
    try t.expectEqual(loads + 1, backend.loads); // Only main reloads; dep uses replacement content.
    try check(a, "globalThis.latest = 0; old.later().then(x=>{latest=x}); true");
    rt.pump();
    try check(a, "latest === 99");
    try t.expectEqual(@as(usize, 2), try a.clearImportCache());
    try t.expectEqual(@as(usize, 0), try a.clearImportCache());
    try exposeModule(a, "main", "cleared");
    try check(a, "cleared.value === 2 && updated.value === 99");
}

test "cache replacement and eviction distinguish canonical import attributes" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    var backend: AttributeBackend = .{};
    const scope = try rt.createScope(backend.options());
    try exposeModule(scope, "main", "old");
    const attrs = [_]m.ImportAttribute{ .{ .key = "type", .value = "custom" }, .{ .key = "mode", .value = "one" } };
    try scope.updateImportCache(.{ .module_id = "payload", .import_attributes = &attrs }, .{ .source = "export const value = 10" }, null);
    try exposeModule(scope, "main", "updated");
    try check(scope, "old.values[0] === 1 && updated.values[0] === 10 && updated.values[1] === 2");
    try t.expectEqual(@as(usize, 2), backend.payload_loads);
    try t.expectEqual(@as(usize, 2), try scope.deleteImportCache(.{ .module_id = "payload", .import_attributes = &attrs }));
    try exposeModule(scope, "main", "reloaded");
    try check(scope, "reloaded.values[0] === 1 && reloaded.values[1] === 2");
    try t.expectEqual(@as(usize, 3), backend.payload_loads);
}

// Local V8 scopes are released before return; no resources escape.
test "cache updates preserve pending imports and retired synthetic metadata" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    var backend: Deferred = .{};
    const scope = try rt.createScope(backend.options());
    const old = try scope.importModule("module", null);
    defer old.deinit();
    try scope.updateImportCache(.{ .module_id = "module" }, .{ .source = "export const value = 3" }, null);
    const fresh = try scope.importModule("module", null);
    defer fresh.deinit();
    try expectState(&rt, fresh, .Fulfilled);
    try expectState(&rt, old, .Pending);
    const seven = try scope.eval("7", "test:synthetic", null);
    defer seven.deinit();
    const exports = [_]m.Export{.{ .name = "value", .value = seven }};
    try rt.completeLoad(backend.tokens[0], .{ .content = .{ .exports = &exports } });
    rt.pump();
    try expectState(&rt, old, .Fulfilled);
    rt.isolate.enter();
    defer rt.isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(rt.isolate);
    defer h_scope.deinit();
    const ctx = scope.context.deref();
    ctx.enter();
    defer ctx.exit();
    try t.expectEqual(@as(i32, 7), old.deref().result().toObject(ctx).?.get(ctx, v8.String.initUtf8(rt.isolate, "value").name.primitive.value).?.i32Value(ctx).?);
    try t.expectEqual(@as(i32, 3), fresh.deref().result().toObject(ctx).?.get(ctx, v8.String.initUtf8(rt.isolate, "value").name.primitive.value).?.i32Value(ctx).?);
    const deleted = try scope.importModule("pending-delete", null);
    defer deleted.deinit();
    try t.expectEqual(@as(usize, 1), try scope.deleteImportCache(.{ .module_id = "pending-delete" }));
    const reloaded = try scope.importModule("pending-delete", null);
    defer reloaded.deinit();
    try t.expectEqual(@as(usize, 3), backend.count);
    try rt.completeLoad(backend.tokens[1], .{ .content = .{ .source = "export const old = true" } });
    try rt.completeLoad(backend.tokens[2], .{ .content = .{ .source = "export const old = false" } });
    rt.pump();
    try expectState(&rt, deleted, .Fulfilled);
    try expectState(&rt, reloaded, .Fulfilled);
    try t.expectError(error.StaleLoadToken, rt.completeLoad(backend.tokens[0], .{ .failure = error.NotFound }));
}

test "cache operations support cycles, cached failures and insertion without loading" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    var backend: Memory = .{};
    const scope = try rt.createScope(backend.options());
    try exposeModule(scope, "cycle-a", "old");
    try scope.updateImportCache(.{ .module_id = "cycle-b" }, .{ .source = "import {a} from 'cycle-a'; export function b(){return a+10}" }, null);
    try exposeModule(scope, "cycle-a", "fresh");
    try check(scope, "old.read() === 3 && fresh.read() === 13");
    try t.expectError(error.JavaScriptException, scope.updateImportCache(.{ .module_id = "inserted" }, .{ .source = "export const =" }, null));
    const failed = try scope.importModule("inserted", null);
    defer failed.deinit();
    try expectState(&rt, failed, .Rejected);
    const loads = backend.loads;
    try scope.updateImportCache(.{ .module_id = "inserted" }, .{ .source = "export const value = 42" }, null);
    try exposeModule(scope, "inserted", "inserted");
    try check(scope, "inserted.value === 42");
    try t.expectEqual(loads, backend.loads);
    const missing = try scope.importModule("missing", null);
    defer missing.deinit();
    try expectState(&rt, missing, .Rejected);
    try t.expectEqual(@as(usize, 1), try scope.deleteImportCache(.{ .module_id = "missing" }));
}

test "cache mutation is rejected during loader callbacks" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const Backend = struct {
        scope: *m.Scope = undefined,
        fn load(data: ?*anyopaque, _: m.LoadRequest) !m.LoadResult {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            try t.expectError(error.ImportCacheBusy, self.scope.clearImportCache());
            return .{ .source = "export const value = 42" };
        }
    };
    var backend: Backend = .{};
    const scope = try rt.createScope(.{ .resolver = .{ .resolve = Memory.resolve }, .loader = .{ .data = &backend, .load = Backend.load } });
    backend.scope = scope;
    try exposeModule(scope, "main", "module");
    try check(scope, "module.value === 42");
}

fn expectMapResolution(map: *m.ImportMap, specifier: []const u8, referrer: []const u8, expected: []const u8) !void {
    const result = try map.resolve(t.allocator, specifier, referrer);
    defer t.allocator.free(result);
    try t.expectEqualStrings(expected, result);
}

/// Reads allocator accounting without retaining or mutating the allocator.
fn retainedBytes(alloc: *const t.FailingAllocator) usize {
    return alloc.allocated_bytes - alloc.freed_bytes;
}

test "managed allocations: cache hits, deletion misses and resolution errors retain no scratch" {
    @import("../test.zig").ensureV8();
    var accounting = t.FailingAllocator.init(t.allocator, .{});
    var rt = m.Runtime.init(accounting.allocator());
    const Backend = struct {
        loads: usize = 0,
        saved_id: []const u8 = "",
        saved_attributes: []const m.ImportAttribute = &.{},
        fn load(data: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            self.loads += 1;
            self.saved_id = request.module_id;
            self.saved_attributes = request.import_attributes;
            return .{ .source = "export const value = 1" };
        }
    };
    var backend: Backend = .{};
    var import_map_5 = try m.ImportMap.parseJson(t.allocator, "{\"imports\":{\"ok\":\"./ok.js\"}}", .{ .base_url = "app:/map.json", .urls = m.virtual_urls });
    defer import_map_5.deinit();
    const scope = try rt.createScope(.{
        .import_map = &import_map_5,
        .loader = .{ .data = &backend, .load = Backend.load },
    });
    var key = [_]u8{ 't', 'y', 'p', 'e' };
    var value = [_]u8{ 'j', 's', 'o', 'n' };
    const attributes = [_]m.ImportAttribute{ .{ .key = &key, .value = &value }, .{ .key = "mode", .value = "one" } };
    {
        const first = try scope.importModuleWithAttributes("ok", &attributes, null);
        defer first.deinit();
        try expectState(&rt, first, .Fulfilled);
    }
    const baseline = retainedBytes(&accounting);
    for (0..100) |_| {
        const cached = try scope.importModuleWithAttributes("ok", &.{ attributes[1], attributes[0] }, null);
        defer cached.deinit();
        try expectState(&rt, cached, .Fulfilled);
        try t.expectEqual(@as(usize, 0), try scope.deleteImportCache(.{ .module_id = "absent", .import_attributes = &attributes }));
        const denied = try scope.importModule("missing", null);
        defer denied.deinit();
        try expectState(&rt, denied, .Rejected);
        const invalid = try scope.importModule("app:/bad%zz", null);
        defer invalid.deinit();
        try expectState(&rt, invalid, .Rejected);
        try t.expectEqual(baseline, retainedBytes(&accounting));
    }
    @memset(&key, 'x');
    @memset(&value, 'x');
    try t.expectEqualStrings("app:/ok.js", backend.saved_id);
    try t.expectEqualStrings("type", backend.saved_attributes[1].key);
    try t.expectEqualStrings("json", backend.saved_attributes[1].value);
    try t.expectEqual(@as(usize, 1), backend.loads);
    rt.deinit();
    try t.expectEqual(@as(usize, 0), retainedBytes(&accounting));
}

test "managed allocations: direct import-map and normalizer results are caller owned" {
    var accounting = t.FailingAllocator.init(t.allocator, .{});
    const alloc = accounting.allocator();
    const json = try alloc.dupe(u8, "{\"imports\":{\"exact\":\"./exact.js\",\"pkg/\":\"./packages/\",\"blocked\":null}}");
    var map = try m.ImportMap.parseJson(alloc, json, .{ .base_url = "app:/map.json", .urls = m.virtual_urls });
    @memset(json, 'x');
    alloc.free(json);
    const baseline = retainedBytes(&accounting);
    for (0..50) |_| {
        for ([_][]const u8{ "exact", "pkg/a.js", "./relative.js" }) |specifier| {
            const result = try map.resolve(alloc, specifier, "app:/main.js");
            alloc.free(result);
            try t.expectEqual(baseline, retainedBytes(&accounting));
        }
        try t.expectError(error.BlockedImport, map.resolve(alloc, "blocked", ""));
        try t.expectError(error.ImportMapBacktracking, map.resolve(alloc, "pkg/%2e%2e/escape.js", ""));
        try t.expectEqual(baseline, retainedBytes(&accounting));
    }
    const result = try map.resolve(alloc, "exact", "");
    map.deinit();
    try t.expectEqualStrings("app:/exact.js", result);
    alloc.free(result);
    const normalized = try m.virtual_urls.normalize(null, alloc, "APP:/a/%2e%2e/b.js?q=%2e%2f", "");
    try t.expectEqualStrings("app:/b.js?q=%2e%2f", normalized);
    alloc.free(normalized);
    try t.expectError(error.InvalidVirtualURL, m.virtual_urls.normalize(null, alloc, "app:/bad%zz", ""));
    try t.expectEqual(@as(usize, 0), retainedBytes(&accounting));
}

/// Borrows alloc for the map and result lifetimes; releases every map/result
/// before return or error. Disables resizing so failure indices do not depend on
/// incidental backing-allocator in-place growth. Retains no resources.
fn mapAllocationFailures(alloc: std.mem.Allocator) !void {
    var no_resize = t.FailingAllocator.init(alloc, .{ .resize_fail_index = 0 });
    const stable_alloc = no_resize.allocator();
    var map = try m.ImportMap.parseJson(stable_alloc, "{\"imports\":{\"exact\":\"./a.js\",\"pkg/\":\"./pkg/\"},\"scopes\":{\"./scope/\":{\"exact\":\"./b.js\"}}}", .{
        .base_url = "APP:/map.json",
        .urls = m.virtual_urls,
    });
    defer map.deinit();
    const scoped = try map.resolve(stable_alloc, "exact", "app:/scope/main.js");
    defer stable_alloc.free(scoped);
    try t.expectEqualStrings("app:/b.js", scoped);
    const prefix = try map.resolve(stable_alloc, "pkg/a.js", "");
    defer stable_alloc.free(prefix);
    try t.expectEqualStrings("app:/pkg/a.js", prefix);
}

test "managed allocations: map creation and resolution clean up at every allocation failure" {
    try t.checkAllAllocationFailures(t.allocator, mapAllocationFailures, .{});
}

/// Borrows alloc through Runtime.deinit and releases all runtime/map allocations
/// before return or error. Retains no resources.
fn scopeAllocationFailures(alloc: std.mem.Allocator) !void {
    var rt = m.Runtime.init(alloc);
    defer rt.deinit();
    var import_map_6 = try m.ImportMap.parseJson(t.allocator, "{\"imports\":{\"ok\":\"./ok.js\"}}", .{ .base_url = "app:/map.json", .urls = m.virtual_urls });
    defer import_map_6.deinit();
    _ = try rt.createScope(.{
        .import_map = &import_map_6,
    });
}

test "managed allocations: scope creation cleans up at every allocation failure" {
    @import("../test.zig").ensureV8();
    try t.checkAllAllocationFailures(t.allocator, scopeAllocationFailures, .{});
}

test "managed allocations: nested dynamic imports keep operation scratch independent" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const Backend = struct {
        fn load(_: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
            if (std.mem.eql(u8, request.module_id, "outer")) return .{ .source = "export const value = (await import('middle')).value + 1" };
            if (std.mem.eql(u8, request.module_id, "middle")) return .{ .source = "export const value = (await import('inner')).value + 1" };
            return .{ .source = "export const value = 40" };
        }
    };
    const scope = try rt.createScope(.{ .resolver = .{ .resolve = Memory.resolve }, .loader = .{ .load = Backend.load } });
    try exposeModule(scope, "outer", "nested");
    try check(scope, "nested.value === 42");
}

// Local V8 scopes are released before return; no resources escape.
test "managed allocations: replacement OOM preserves old cache and pending imports" {
    @import("../test.zig").ensureV8();
    var checked_failures: usize = 0;
    var offset: usize = 0;
    while (offset < 64) : (offset += 1) {
        var accounting = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
        {
            var rt = m.Runtime.init(accounting.allocator());
            defer rt.deinit();
            var backend: Deferred = .{};
            const scope = try rt.createScope(backend.options());
            const pending = try scope.importModule("module", null);
            defer pending.deinit();
            // Force persistent promotion to need a backing allocation rather than
            // depending on the arena's incidental spare capacity.
            const long_value = try t.allocator.alloc(u8, 16 * 1024);
            defer t.allocator.free(long_value);
            @memset(long_value, 'a');
            const attributes = [_]m.ImportAttribute{.{ .key = "format", .value = long_value }};
            try scope.updateImportCache(.{ .module_id = "stable", .import_attributes = &attributes }, .{ .source = "export const value = 1" }, null);
            accounting.fail_index = accounting.alloc_index + offset;
            const outcome = scope.updateImportCache(.{ .module_id = "stable", .import_attributes = &attributes }, .{ .source = "export const value = 99" }, null);
            accounting.fail_index = std.math.maxInt(usize);
            if (outcome) |_| {
                try t.expect(!accounting.has_induced_failure);
            } else |err| {
                try t.expectEqual(error.OutOfMemory, err);
                checked_failures += 1;
            }
            const imported = try scope.importModuleWithAttributes("stable", &attributes, null);
            defer imported.deinit();
            try expectState(&rt, imported, .Fulfilled);
            rt.isolate.enter();
            {
                defer rt.isolate.exit();
                var h_scope: v8.HandleScope = undefined;
                h_scope.init(rt.isolate);
                defer h_scope.deinit();
                const ctx = scope.context.deref();
                ctx.enter();
                defer ctx.exit();
                const actual = imported.deref().result().toObject(ctx).?.get(ctx, v8.String.initUtf8(rt.isolate, "value").name.primitive.value).?.i32Value(ctx).?;
                try t.expectEqual(@as(i32, if (accounting.has_induced_failure) 1 else 99), actual);
            }
            try expectState(&rt, pending, .Pending);
            try rt.completeLoad(backend.tokens[0], .{ .content = .{ .source = "export const value = 7" } });
            rt.pump();
            try expectState(&rt, pending, .Fulfilled);
        }
        try t.expectEqual(@as(usize, 0), retainedBytes(&accounting));
        if (!accounting.has_induced_failure) break;
    }
    try t.expect(checked_failures >= 2);
    try t.expect(offset < 64);
}

test "managed allocations: import OOM releases lookup and entry storage at teardown" {
    @import("../test.zig").ensureV8();
    const Backend = struct {
        fn load(_: ?*anyopaque, _: m.LoadRequest) !m.LoadResult {
            return .{ .source = "export const value = 1" };
        }
    };
    var offset: usize = 0;
    var failures: usize = 0;
    while (offset < 64) : (offset += 1) {
        var accounting = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
        {
            var rt = m.Runtime.init(accounting.allocator());
            defer rt.deinit();
            const scope = try rt.createScope(.{ .resolver = .{ .resolve = Memory.resolve }, .loader = .{ .load = Backend.load } });
            accounting.fail_index = accounting.alloc_index + offset;
            const outcome = scope.importModuleWithAttributes("new-entry", &.{.{ .key = "type", .value = "custom" }}, null);
            accounting.fail_index = std.math.maxInt(usize);
            if (outcome) |promise| {
                defer promise.deinit();
                try expectState(&rt, promise, if (accounting.has_induced_failure) .Rejected else .Fulfilled);
            } else |err| try t.expectEqual(error.OutOfMemory, err);
            if (accounting.has_induced_failure) failures += 1;
            const recovered = try scope.importModule("recovery", null);
            defer recovered.deinit();
            try expectState(&rt, recovered, .Fulfilled);
        }
        try t.expectEqual(@as(usize, 0), retainedBytes(&accounting));
        if (!accounting.has_induced_failure) break;
    }
    try t.expect(failures >= 3);
    try t.expect(offset < 64);
}

test "ownership contract: public slice inputs may be released immediately after return" {
    @import("../test.zig").ensureV8();
    var rt = m.Runtime.init(t.allocator);
    defer rt.deinit();
    const json = try t.allocator.dupe(u8, "{\"imports\":{\"item\":\"./item.js\"}}");
    const base = try t.allocator.dupe(u8, "app:/map.json");
    var import_map_7 = try m.ImportMap.parseJson(t.allocator, json, .{ .base_url = base, .urls = m.virtual_urls });
    defer import_map_7.deinit();
    const scope = try rt.createScope(.{ .import_map = &import_map_7 });
    t.allocator.free(json);
    t.allocator.free(base);
    try t.expect(scope.options.import_map == null);
    const source = try t.allocator.dupe(u8, "({answer:42})");
    const origin = try t.allocator.dupe(u8, "app:/origin.js");
    const cap = try scope.eval(source, origin, null);
    t.allocator.free(source);
    t.allocator.free(origin);
    const cap_name = try t.allocator.dupe(u8, "capability");
    try scope.installCapability(cap_name, cap, null);
    t.allocator.free(cap_name);
    const id = try t.allocator.dupe(u8, "app:/item.js");
    const export_name = try t.allocator.dupe(u8, "value");
    const exports = try t.allocator.alloc(m.Export, 1);
    exports[0] = .{ .name = export_name, .value = cap };
    try scope.updateImportCache(.{ .module_id = id }, .{ .exports = exports }, null);
    t.allocator.free(id);
    t.allocator.free(export_name);
    t.allocator.free(exports);
    cap.deinit();
    try exposeModule(scope, "item", "owned");
    try check(scope, "owned.value === capability && owned.value.answer === 42");
    const replacement_id = try t.allocator.dupe(u8, "app:/item.js");
    const replacement_source = try t.allocator.dupe(u8, "export const value = 99");
    try scope.updateImportCache(.{ .module_id = replacement_id }, .{ .source = replacement_source }, null);
    t.allocator.free(replacement_id);
    t.allocator.free(replacement_source);
    try exposeModule(scope, "item", "replacement");
    try check(scope, "replacement.value === 99 && owned.value.answer === 42");
}
