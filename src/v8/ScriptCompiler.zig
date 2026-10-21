const v8Binding = @import("../generated/binding.zig");
const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const ScriptCompiler = extern struct {
    /// Owns cached code allocated by V8. Source takes ownership of cached data passed to init.
    pub const CachedData = extern struct {
        pub const Opaque = opaque {};
        handle: *Opaque,
        pub fn init(data: ?[*]const u8, length: c_int) ?v8.ScriptCompiler.CachedData {
            return .{ .handle = e.v8__ScriptCompiler__CachedData__NEW(data, length) orelse return null };
        }

        pub fn deinit(self: v8.ScriptCompiler.CachedData) void {
            e.v8__ScriptCompiler__CachedData__DELETE(self.handle);
        }

        /// Leading fields of V8's `CachedData`; the binding asserts these offsets.
        const Layout = extern struct { data: ?[*]const u8, length: c_int, rejected: bool };

        /// Borrows the cache; the bytes belong to it (or to the buffer it was created over)
        /// and are valid until `deinit` or, for a cache a Source owns, the Source's `deinit`.
        pub fn bytes(handle: *const Opaque) []const u8 {
            const layout: *const Layout = @ptrCast(@alignCast(handle));
            return (layout.data orelse return &.{})[0..@intCast(layout.length)];
        }

        /// Whether V8 refused the cache during a compile that consumed it (version, flags or
        /// source mismatch). Only meaningful after that compile. Borrows the cache.
        pub fn rejected(handle: *const Opaque) bool {
            const layout: *const Layout = @ptrCast(@alignCast(handle));
            return layout.rejected;
        }
    };
    /// Construct in its final address, and call deinit before releasing storage.
    pub const Source = extern struct {
        storage: [v8Binding.sizes.ScriptCompiler_Source]u8 align(@alignOf(usize)),
        pub fn init(buf: *v8.ScriptCompiler.Source, source_string: v8.String, origin: ?*const v8.ScriptOrigin, cached_data: ?v8.ScriptCompiler.CachedData) void {
            e.v8__ScriptCompiler__Source__CONSTRUCT(buf, source_string, if (origin) |v| &v.inner else null, if (cached_data) |v| v.handle else null);
        }

        pub fn deinit(self: *v8.ScriptCompiler.Source) void {
            e.v8__ScriptCompiler__Source__DESTRUCT(self);
        }

        pub fn getCachedData(source: *const v8.ScriptCompiler.Source) ?*const CachedData.Opaque {
            return e.v8__ScriptCompiler__Source__GetCachedData(source);
        }
    };

    pub fn compileModule(isolate: v8.Isolate, source: ?*v8.ScriptCompiler.Source, options: u32, no_cache_reason: u32) ?v8.Module {
        return v8.Module.from_opaque(e.v8__ScriptCompiler__CompileModule(isolate.handle, source, options, no_cache_reason));
    }

    pub fn compile(context: ?v8.Context, source: ?*v8.ScriptCompiler.Source, options: u32, no_cache_reason: u32) ?v8.Script {
        return v8.Script.from_opaque(e.v8__ScriptCompiler__Compile(if (context) |v| v8.support.rawHandle(v) else null, source, options, no_cache_reason));
    }

    pub fn compileFunction(context: ?v8.Context, source: ?*v8.ScriptCompiler.Source, arguments: []const v8.String, context_extensions: []const v8.Object, options: u32, no_cache_reason: u32) ?v8.Function {
        return v8.Function.from_opaque(e.v8__ScriptCompiler__CompileFunction(if (context) |v| v8.support.rawHandle(v) else null, source, arguments.len, @ptrCast(arguments.ptr), context_extensions.len, @ptrCast(context_extensions.ptr), options, no_cache_reason));
    }

    pub fn compileUnboundScript(isolate: v8.Isolate, source: ?*v8.ScriptCompiler.Source, options: u32, no_cache_reason: u32) ?v8.UnboundScript {
        return v8.UnboundScript.from_opaque(e.v8__ScriptCompiler__CompileUnboundScript(isolate.handle, source, options, no_cache_reason));
    }

    pub fn cachedDataVersionTag() u32 {
        return e.v8__ScriptCompiler__CachedDataVersionTag();
    }
};
