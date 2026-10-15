const std = @import("std");
const v8 = @import("../v8.zig");
const modules = @import("modules.zig");
const import_map = @import("import_map.zig");
const startup_trace = @import("../startup_trace.zig");
pub const supported_v8_version = "15.2.124.1";

/// Caller-owned error details. Initialize with .{}; do not copy populated instances.
/// Passing &info borrows it through the call and releases any previous details first.
/// Call deinit before Runtime.deinit; passing null discards error details.
pub const ErrorInfo = struct {
    /// Retained original thrown/cached JS value, owned by this ErrorInfo. Null on
    /// success or when no JS value was caught (including engine termination).
    /// Borrow it for inspection; do not independently deinit it or outlive ErrorInfo.
    exception: ?v8.Global.Of(v8.Value) = null,

    /// Releases retained error details and resets this value; safe to call repeatedly.
    /// The originating Runtime must still be alive.
    pub fn deinit(self: *ErrorInfo) void {
        if (self.exception) |exception| exception.deinit();
        self.* = .{};
    }
};

/// Borrows the local TryCatch value through the call; copies a caught exception
/// into error_info only when its slot is empty. The caller owns/deinitializes it.
fn retainException(isolate: v8.Isolate, tc_scope: *const v8.TryCatch, error_info: ?*ErrorInfo) void {
    if (error_info) |out| if (out.exception == null) {
        if (tc_scope.getException()) |exception| out.exception = .new(isolate, exception);
    };
}

pub const Runtime = struct {
    pub const Options = struct {
        /// Default uses V8's native allocator. zig creates a runtime-owned adapter;
        /// its allocator state must be thread-safe and live through Runtime.deinit.
        /// borrowed leaves native allocator ownership with the caller, who must
        /// retain it until the runtime and all its backing stores have been released.
        array_buffer_allocator: union(enum) {
            default,
            zig: std.mem.Allocator,
            borrowed: v8.ArrayBuffer.Allocator,
        } = .default,
    };
    isolate: v8.Isolate,
    array_buffer_allocator: v8.ArrayBuffer.Allocator,
    owns_array_buffer_allocator: bool = true,
    allocator: std.mem.Allocator,
    scopes: std.ArrayList(*Scope) = .empty,
    queue: v8.MicrotaskQueue,
    next_load_token: modules.LoadToken = 1,

    /// Borrows alloc/state through deinit. Returns an owning Runtime: do not copy;
    /// keep its address stable after createScope. Release caller V8 handles and all
    /// standalone/shared backing stores before deinit; owns V8's default allocator.
    pub fn init(alloc: std.mem.Allocator) Runtime {
        return initWithAllocator(alloc, v8.ArrayBuffer.Allocator.initDefault(), true);
    }

    /// Borrows metadata alloc/state through deinit. Copies options; zig adapters
    /// are owned by the runtime, while borrowed allocators remain caller-owned.
    /// Release all V8 handles and backing stores before deinit when using an owned
    /// allocator; a borrowed allocator can outlive the runtime for retained stores.
    /// On adapter failure no resources are retained. V8 isolate OOM remains fatal.
    /// Returns an owning runtime; keep its address stable after createScope.
    pub fn initWithOptions(alloc: std.mem.Allocator, options: Options) !Runtime {
        const aba = switch (options.array_buffer_allocator) {
            .default => v8.ArrayBuffer.Allocator.initDefault(),
            .zig => |backing_alloc| try v8.ArrayBuffer.Allocator.fromZig(backing_alloc),
            .borrowed => |provided| provided,
        };
        return initWithAllocator(alloc, aba, options.array_buffer_allocator != .borrowed);
    }

    /// Copies alloc/aba descriptors; retains their state through runtime teardown.
    /// Takes aba ownership only when owns_aba is true. Creates isolate-owned state;
    /// V8 may terminate on isolate initialization OOM. Returns an owning runtime.
    fn initWithAllocator(alloc: std.mem.Allocator, aba: v8.ArrayBuffer.Allocator, owns_aba: bool) Runtime {
        var params = v8.Isolate.CreateParams.init();
        params.array_buffer_allocator = aba;
        params.allow_atomics_wait = false;
        const isolate = v8.Isolate.init(&params);
        isolate.enter();
        defer isolate.exit();
        isolate.setMicrotasksPolicy(.Explicit);
        isolate.setAllowWasmCodeGenerationCallback(denyWasm);
        isolate.setHostImportModuleDynamicallyCallback(modules.dynamic);
        isolate.setHostImportModuleWithPhaseDynamicallyCallback(modules.dynamicPhase);
        isolate.setHostInitializeImportMetaObjectCallback(modules.importMeta);
        return .{ .isolate = isolate, .array_buffer_allocator = aba, .owns_array_buffer_allocator = owns_aba, .allocator = alloc, .queue = .init(isolate, .Explicit) };
    }

    /// Frees runtime-owned slices/scopes/handles, invalidating borrowed request bytes.
    /// Never frees callback data; host-owned state must stay alive through this call.
    /// Releases an owned backing-store allocator after isolate disposal. External
    /// backing-store references must already be released unless its allocator is borrowed.
    pub fn deinit(self: *Runtime) void {
        self.isolate.enter();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(self.isolate);
        for (self.scopes.items) |scope| {
            const ctx = scope.context.deref();
            ctx.enter();
            scope.module_map.deinit();
            ctx.exit();
            scope.hardener.deinit();
            scope.unsupported_prototype.deinit();
            if (scope.import_map) |map| {
                map.deinit();
                self.allocator.destroy(map);
            }
            scope.context.deinit();
            self.allocator.destroy(scope);
        }
        self.scopes.deinit(self.allocator);
        h_scope.deinit();
        self.queue.deinit();
        self.isolate.exit();
        self.isolate.deinit();
        if (self.owns_array_buffer_allocator) self.array_buffer_allocator.deinit();
    }

    /// Borrows options/import_map only through return; map entries are cloned.
    /// Callback descriptors are copied but data pointers remain host-owned and must
    /// stay stable/alive through Runtime.deinit. Returns a runtime-owned Scope pointer;
    /// do not free/copy it or use it after runtime teardown.
    /// With V8_STARTUP_TRACE set, retains only static timing labels in a bounded
    /// thread-local buffer until startup_trace.report; errors retain partial timings.
    /// Bootstrap borrows GC-owned intrinsic/prototype arrays only through its
    /// initializer call; retained helper closures expire with this scope.
    /// Errors release persistent handles, cloned maps, and partial scope state.
    pub fn createScope(self: *Runtime, options: Scope.Options) !*Scope {
        var timing = startup_trace.begin();
        const version = v8.V8.getVersion();
        var numeric_end: usize = 0;
        while (numeric_end < version.len and (std.ascii.isDigit(version[numeric_end]) or version[numeric_end] == '.')) : (numeric_end += 1) {}
        // V8 appends an embedder suffix (this build uses "-lightpanda").
        if (!std.mem.eql(u8, version[0..numeric_end], supported_v8_version)) return error.UnsupportedV8Version;
        self.isolate.enter();
        defer self.isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(self.isolate);
        defer h_scope.deinit();
        const scope = try self.allocator.create(Scope);
        errdefer self.allocator.destroy(scope);
        const ctx = v8.Context.init(self.isolate, null, null, self.queue);
        startup_trace.mark(&timing, "context_create");
        scope.* = .{ .runtime = self, .id = self.scopes.items.len, .context = .new(self.isolate, ctx), .options = options };
        errdefer scope.context.deinit();
        scope.module_map = .init(scope);
        errdefer scope.module_map.deinit();
        if (options.import_map) |provided| {
            if (options.resolver != null) return error.ConflictingResolvers;
            const map = try self.allocator.create(import_map.ImportMap);
            errdefer self.allocator.destroy(map);
            map.* = try provided.clone(self.allocator);
            scope.import_map = map;
            scope.options.resolver = map.resolver();
        }
        errdefer if (scope.import_map) |map| {
            map.deinit();
            self.allocator.destroy(map);
        };
        ctx.setSecurityToken(v8.Symbol.init(self.isolate, null).name.primitive.value);
        // Retain only our independent copy, not the caller's map pointer.
        scope.options.import_map = null;
        ctx.setAlignedPointerInEmbedderData(1, scope);
        ctx.enter();
        defer ctx.exit();
        var tc_scope: v8.TryCatch = undefined;
        tc_scope.init(self.isolate);
        defer tc_scope.deinit();
        startup_trace.mark(&timing, "scope_host_setup");
        const bootstrap = v8.Script.compile(ctx, v8.String.initUtf8(self.isolate, @embedFile("bootstrap.js")), null) orelse return error.BootstrapFailed;
        startup_trace.mark(&timing, "bootstrap_compile");
        const initializer_value = bootstrap.run(ctx) orelse return error.BootstrapFailed;
        const initializer = v8.Function.from_opaque(initializer_value.data.handle) orelse return error.BootstrapFailed;
        const intrinsic_objects = v8.Intrinsics.getObjects(ctx) orelse return error.BootstrapFailed;
        if (intrinsic_objects.len() == 0) return error.BootstrapFailed;
        const unsupported_objects = v8.Array.init(self.isolate, 5);
        inline for (.{ .array_iterator, .string_iterator, .regexp_string_iterator, .iterator_helper, .iterator_wrapper }, 0..) |prototype, index| {
            const object = v8.Intrinsics.getPrototype(ctx, prototype) orelse return error.BootstrapFailed;
            if (!(unsupported_objects.object.setIndex(ctx, index, object.value) orelse return error.BootstrapFailed)) return error.BootstrapFailed;
        }
        const helper_value = initializer.call(ctx, v8.Primitive.initUndefined(self.isolate).value, &.{ intrinsic_objects.object.value, unsupported_objects.object.value }) orelse return error.BootstrapFailed;
        const helper = helper_value.toObject(ctx) orelse return error.BootstrapFailed;
        startup_trace.mark(&timing, "bootstrap_run_harden");
        const hardener = helper.getIndex(ctx, 0) orelse return error.BootstrapFailed;
        scope.hardener = .new(self.isolate, v8.Function.from_opaque(hardener.data.handle) orelse return error.BootstrapFailed);
        errdefer scope.hardener.deinit();
        const unsupported = helper.getIndex(ctx, 1) orelse return error.BootstrapFailed;
        scope.unsupported_prototype = .new(self.isolate, v8.Function.from_opaque(unsupported.data.handle) orelse return error.BootstrapFailed);
        errdefer scope.unsupported_prototype.deinit();
        ctx.allowCodeGenerationFromStrings(false);
        try self.scopes.append(self.allocator, scope);
        startup_trace.mark(&timing, "scope_finalize");
        return scope;
    }

    pub fn pump(self: *Runtime) void {
        self.isolate.enter();
        defer self.isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(self.isolate);
        defer h_scope.deinit();
        while (true) {
            self.queue.performCheckpoint(self.isolate);
            var progress = false;
            // Guest execution can create import tasks, but cannot create scopes.
            for (self.scopes.items) |scope| {
                const ctx = scope.context.deref();
                ctx.enter();
                progress = scope.module_map.drive() or progress;
                ctx.exit();
            }
            if (!progress) break;
        }
    }

    /// Drain V8 foreground tasks with the isolate entered, then managed jobs.
    pub fn pumpPlatform(self: *Runtime, platform: v8.Platform) void {
        self.isolate.enter();
        defer self.isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(self.isolate);
        defer h_scope.deinit();
        while (platform.pumpMessageLoop(self.isolate, false)) {}
        self.pump();
    }

    /// Complete on the owning isolate thread, after the loader callback has returned.
    /// Borrows content/nested names/handles through return (including errors).
    /// Accepted strings/handles are copied/retained independently. Caller may free
    /// buffers and release its handles after return. Handles must belong to this runtime.
    pub fn completeLoad(self: *Runtime, token: modules.LoadToken, completion: modules.Completion) !void {
        self.isolate.enter();
        defer self.isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(self.isolate);
        defer h_scope.deinit();
        for (self.scopes.items) |scope| {
            const ctx = scope.context.deref();
            ctx.enter();
            defer ctx.exit();
            if (try scope.module_map.complete(token, completion)) return;
        }
        return error.StaleLoadToken;
    }
};

fn denyWasm(_: v8.Context, _: v8.String) callconv(.c) bool {
    return false;
}

pub const Scope = struct {
    pub const Options = struct {
        /// Optional specifier rewriting before module-map lookup. Without a resolver
        /// or import map, specifiers are used unchanged as module-map keys.
        resolver: ?modules.Resolver = null,
        loader: ?modules.Loader = null,
        /// Per-scope specifier-to-specifier import map, applied before module-map lookup.
        /// Borrows the map through createScope only; entries are cloned per scope.
        /// Caller may reuse/deinit it afterward. URLNormalizer.data remains host-owned
        /// and must stay alive through Runtime.deinit. Do not mutate a scope's copy.
        import_map: ?*const import_map.ImportMap = null,
    };
    runtime: *Runtime,
    id: usize,
    context: v8.Global.Of(v8.Context),
    options: Options,
    hardener: v8.Global.Of(v8.Function) = undefined,
    unsupported_prototype: v8.Global.Of(v8.Function) = undefined,
    /// Owns resolved-specifier/attribute -> V8 module mappings and their load/cache state.
    /// Runtime-owned; use module_map.update/delete/clear/get, never copy or deinit it.
    module_map: modules.ModuleMap = undefined,
    import_map: ?*import_map.ImportMap = null,

    /// Deep-freeze a supported public graph. Hidden closure/private state is intentionally untouched.
    /// Borrows this-runtime persistent handle without consuming it; freezes its graph
    /// in place. Caller owns the handle and must release it before Runtime.deinit.
    /// error_info follows ErrorInfo ownership; also captures UnsupportedExport exceptions.
    pub fn harden(self: *Scope, value: v8.Global.Of(v8.Value), error_info: ?*ErrorInfo) !void {
        if (error_info) |out| out.deinit();
        const isolate = self.runtime.isolate;
        isolate.enter();
        defer isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(isolate);
        defer h_scope.deinit();
        const ctx = self.context.deref();
        ctx.enter();
        defer ctx.exit();
        var tc_scope: v8.TryCatch = undefined;
        tc_scope.init(isolate);
        defer tc_scope.deinit();
        errdefer retainException(isolate, &tc_scope, error_info);
        try self.hardenLocal(value.deref());
    }

    /// Borrows a local handle only through the call. Caller keeps its HandleScope
    /// live and this context entered. Does not retain the handle; freezes in place.
    pub fn hardenLocal(self: *Scope, value: v8.Value) !void {
        const isolate = self.runtime.isolate;
        const ctx = self.context.deref();
        const validator = v8.Function.init(ctx, supportedExport, v8.External.init(isolate, self.runtime).value.data, 1, .Throw, .HasNoSideEffect);
        _ = self.hardener.deref().call(ctx, v8.Primitive.initUndefined(isolate).value, &.{ value, validator.object.value }) orelse return error.UnsupportedExport;
    }

    /// Borrows origin through this call; V8 copies the UTF-8 bytes. Result uses local
    /// handles: caller needs this isolate entered and a live HandleScope, and must
    /// consume the metadata before that HandleScope ends.
    pub fn scriptOrigin(self: *Scope, origin: []const u8, module: bool) v8.ScriptOrigin {
        const iso = self.runtime.isolate;
        const options = v8.PrimitiveArray.init(iso, 1);
        options.set(iso, 0, v8.Number.initUInt(iso, @intCast(self.id)).numeric.primitive);
        return .init(v8.String.initUtf8(iso, origin).name.primitive.value, 0, 0, false, -1, null, false, false, module, options.data);
    }

    /// Borrows specifier through return, even for pending loads; retained IDs are
    /// copied. Caller may free/reuse input afterward. Returns a caller-owned persistent
    /// promise; deinit it before Runtime.deinit. No input ownership transfer.
    /// error_info follows ErrorInfo ownership for synchronous exceptions only;
    /// ordinary module failures are returned as promise rejections.
    pub fn importModule(self: *Scope, specifier: []const u8, error_info: ?*ErrorInfo) !v8.Global.Of(v8.Promise) {
        return self.importModuleWithAttributes(specifier, &.{}, error_info);
    }

    /// Retire this canonical module ID/attribute set and its cached dependents.
    /// Compatibility entry point for module_map.delete; modifies the same ModuleMap.
    /// Borrows key/attribute array/nested strings through return, including errors.
    /// Caller may free/reuse them afterward. Returns a count, not owned memory.
    pub fn deleteImportCache(self: *Scope, key: modules.ImportCacheKey) !usize {
        return self.mutateImportCache(.{ .delete = key }, null);
    }

    /// Replace/insert module content for future imports; existing graphs retain their instances.
    /// Compatibility entry point for module_map.update; modifies the same ModuleMap.
    /// Borrows key/attributes/source/export array/names/handles through return,
    /// including errors. Retained strings/handles are independently copied. Caller
    /// may free/reuse inputs and release its handles afterward. No ownership transfer;
    /// all handles must belong to this runtime.
    /// error_info follows ErrorInfo ownership and captures compilation/hardening exceptions.
    pub fn updateImportCache(self: *Scope, key: modules.ImportCacheKey, content: modules.Content, error_info: ?*ErrorInfo) !void {
        _ = try self.mutateImportCache(.{ .update = .{ .key = key, .content = content } }, error_info);
    }

    /// Returns a count; no caller-owned memory is freed. Existing references remain valid.
    /// Compatibility entry point for module_map.clear; modifies the same ModuleMap.
    pub fn clearImportCache(self: *Scope) !usize {
        return self.mutateImportCache(.clear, null);
    }

    const CacheMutation = union(enum) {
        delete: modules.ImportCacheKey,
        update: struct { key: modules.ImportCacheKey, content: modules.Content },
        clear,
    };
    fn mutateImportCache(self: *Scope, operation: CacheMutation, error_info: ?*ErrorInfo) !usize {
        if (error_info) |out| out.deinit();
        const iso = self.runtime.isolate;
        iso.enter();
        defer iso.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(iso);
        defer h_scope.deinit();
        const ctx = self.context.deref();
        ctx.enter();
        defer ctx.exit();
        var tc_scope: v8.TryCatch = undefined;
        tc_scope.init(iso);
        defer tc_scope.deinit();
        errdefer retainException(iso, &tc_scope, error_info);
        return switch (operation) {
            .delete => |key| try self.module_map.deleteCache(key),
            .clear => try self.module_map.clearCache(),
            .update => |update| blk: {
                try self.module_map.updateCache(update.key, update.content, error_info);
                break :blk 0;
            },
        };
    }

    /// Borrows specifier/attributes/nested strings through return, including errors.
    /// Retained metadata is deep-copied, including pending loads. Caller may free/reuse
    /// inputs afterward. Returns a caller-owned persistent promise; deinit it before
    /// Runtime.deinit. No input ownership transfer.
    /// error_info follows ErrorInfo ownership for synchronous exceptions only;
    /// resolution/link/evaluation failures normally reject the returned promise instead.
    pub fn importModuleWithAttributes(self: *Scope, specifier: []const u8, attributes: []const modules.ImportAttribute, error_info: ?*ErrorInfo) !v8.Global.Of(v8.Promise) {
        if (error_info) |out| out.deinit();
        const iso = self.runtime.isolate;
        iso.enter();
        defer iso.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(iso);
        defer h_scope.deinit();
        const ctx = self.context.deref();
        ctx.enter();
        defer ctx.exit();
        var tc_scope: v8.TryCatch = undefined;
        tc_scope.init(iso);
        defer tc_scope.deinit();
        errdefer retainException(iso, &tc_scope, error_info);
        return .new(iso, try self.module_map.start(specifier, "", attributes));
    }

    /// Borrows name/handle through return. V8 copies name and retains the value;
    /// caller may free name/release its handle afterward. Freezes the graph in place.
    /// Does not consume the caller's handle; it must belong to this runtime.
    /// error_info follows ErrorInfo ownership, including hardening failures.
    pub fn installCapability(self: *Scope, name: []const u8, value: v8.Global.Of(v8.Value), error_info: ?*ErrorInfo) !void {
        try self.harden(value, error_info);
        const isolate = self.runtime.isolate;
        isolate.enter();
        defer isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(isolate);
        defer h_scope.deinit();
        const ctx = self.context.deref();
        ctx.enter();
        defer ctx.exit();
        var tc_scope: v8.TryCatch = undefined;
        tc_scope.init(isolate);
        defer tc_scope.deinit();
        errdefer retainException(isolate, &tc_scope, error_info);
        const ok = ctx.getGlobal().defineOwnProperty(ctx, v8.String.initUtf8(isolate, name).name, value.deref(), .{ .ReadOnly = true, .DontDelete = true }) orelse return error.JavaScriptException;
        if (!ok) return error.CapabilityInstallationFailed;
    }

    /// Caller owns the returned persistent handle. Runtime must remain at its final address.
    /// Borrows source/origin through return, including errors; V8 copies their bytes.
    /// Caller may free/reuse inputs afterward. No source-rewrite allocation or input
    /// ownership transfer. Returns a caller-owned persistent handle; deinit it before
    /// Runtime.deinit. Runtime must stay at its final address.
    /// error_info follows ErrorInfo ownership; captures syntax errors and thrown
    /// values on JavaScriptException. Pass null to discard the exception value.
    pub fn eval(self: *Scope, source: []const u8, origin: []const u8, error_info: ?*ErrorInfo) !v8.Global.Of(v8.Value) {
        if (error_info) |out| out.deinit();
        const isolate = self.runtime.isolate;
        isolate.enter();
        defer isolate.exit();
        var h_scope: v8.HandleScope = undefined;
        h_scope.init(isolate);
        defer h_scope.deinit();
        const ctx = self.context.deref();
        ctx.enter();
        defer ctx.exit();
        var tc_scope: v8.TryCatch = undefined;
        tc_scope.init(isolate);
        defer tc_scope.deinit();
        errdefer retainException(isolate, &tc_scope, error_info);
        const script_origin = self.scriptOrigin(origin, false);
        const script = v8.Script.compile(ctx, v8.String.initUtf8(isolate, source), script_origin) orelse return error.JavaScriptException;
        const result = script.run(ctx) orelse return error.JavaScriptException;
        return .new(isolate, result);
    }
};

fn supportedExport(info: v8.FunctionCallbackInfo) callconv(.c) void {
    const rt: *Runtime = @ptrCast(@alignCast(v8.External.from_opaque(info.data().?.handle).?.pointer()));
    const value = info.get_arg(0);
    var result = info.retval();
    result.setBool(false);
    if (value.isProxy() or value.isExternal() or value.isDate() or value.isRegExp() or
        value.isMap() or value.isSet() or value.isWeakMap() or value.isWeakSet() or
        value.isArrayBuffer() or value.isArrayBufferView() or value.isSharedArrayBuffer() or
        value.isPromise() or value.isGeneratorObject() or value.isMapIterator() or value.isSetIterator() or
        value.isModuleNamespaceObject() or value.isWasmModuleObject() or value.isWasmMemoryObject() or
        value.isArgumentsObject() or value.isNativeError() or value.isBooleanObject() or
        value.isNumberObject() or value.isStringObject() or value.isSymbolObject() or value.isBigIntObject()) return;
    if (value.isObject()) {
        const object = value.toObject(rt.isolate.getCurrentContext()) orelse return;
        const origin = object.getCreationContext() orelse return;
        var managed = false;
        for (rt.scopes.items) |scope| {
            const ctx = scope.context.deref();
            if (ctx.getGlobal().value.strictEquals(value)) return;
            if (ctx.eq(origin)) managed = true;
            const unsupported = scope.unsupported_prototype.deref().call(ctx, v8.Primitive.initUndefined(rt.isolate).value, &.{value}) orelse return;
            if (unsupported.isTrue()) return;
        }
        if (!managed) return;
    }
    result.setBool(true);
}
