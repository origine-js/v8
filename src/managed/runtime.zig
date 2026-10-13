pub const Runtime = struct {
    isolate: v8.Isolate,
    array_buffer_allocator: v8.ArrayBuffer.Allocator,
    realm: JsRealm,

    pub const Callback = struct {
        pub fn hostImportModuleWithPhaseDynamically(
            js_context: v8.Context,
            js_host_defined_options: v8.Data,
            js_resource_name: v8.Value,
            js_specifier: v8.String,
            phase: v8.ModuleImportPhase,
            js_import_attributes: v8.FixedArray,
        ) callconv(.c) v8.Promise {
            // _ = host_defined_options;
            _ = js_resource_name;
            // _ = specifier;
            _ = phase;
            _ = js_import_attributes;
            const isolate = v8.Isolate.getCurrent();
            const realm: *JsRealm = @ptrCast(@alignCast(v8.External.from_opaque(js_context.getEmbedderData(0).handle).?.pointer()));

            const alloc = realm.alloc;

            const primitive_array: v8.PrimitiveArray = v8.PrimitiveArray.from_opaque(js_host_defined_options.handle).?;
            const map_id = primitive_array.get(isolate, 0).value.u32Value(js_context) orelse unreachable;
            const map = realm.maps.get(@truncate(map_id)) orelse @panic("invalid map");
            var buf: std.ArrayList(u8) = .empty;
            defer buf.deinit(alloc);
            const specifier = u.stringToSlice(
                isolate,
                js_specifier,
                &buf,
                alloc,
            );

            const maybe_mod_id = map.lookup(specifier) catch unreachable orelse blk: {
                var buf1: std.ArrayList(u8) = .empty;
                defer buf1.deinit(alloc);
                const resolver_id = primitive_array.get(isolate, 1).value.u32Value(js_context) orelse unreachable;
                const resolver = realm.resolvers.get(@truncate(resolver_id)) orelse @panic("invalid resolver");
                const new_specifier = resolver.resolve(
                    specifier,
                    &buf1,
                    realm,
                ) orelse break :blk null;
                break :blk map.lookup(new_specifier) catch unreachable;
            };
            std.debug.print("@import(:{s}:) = {?d}\n", .{ specifier, maybe_mod_id });
            const promise_resolver = v8.Promise.Resolver.init(js_context) orelse unreachable;
            if (maybe_mod_id) |mod_id| {
                _ = promise_resolver.resolve(js_context, v8.Number.initUInt(isolate, mod_id).numeric.primitive.value);
            } else {
                _ = promise_resolver.reject(js_context, v8.String.initOneByteStatic(isolate, "module not found").name.primitive.value);
            }
            return promise_resolver.getPromise();
        }
    };

    pub fn init(alloc: std.mem.Allocator) @This() {
        var params: v8.Isolate.CreateParams = .init();
        const aba = v8.ArrayBuffer.Allocator.initDefault();
        params.array_buffer_allocator = aba;

        const isolate: v8.Isolate = .init(&params);
        isolate.setHostImportModuleWithPhaseDynamicallyCallback(&Runtime.Callback.hostImportModuleWithPhaseDynamically);

        return .{
            .isolate = isolate,
            .array_buffer_allocator = aba,
            .realm = .init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.isolate.deinit();
        self.array_buffer_allocator.deinit();
    }

    pub fn context(self: *@This()) v8.Context {
        const js_context = v8.Context.init(self.isolate, null, null, null);
        js_context.setEmbedderData(0, v8.External.init(self.isolate, &self.realm).value.data);
        return js_context;
    }

    pub fn script_origin(
        self: *@This(),
        resource_name: v8.Value,
        resource_line_offset: c_int,
        resource_column_offset: c_int,
        resource_is_shared_cross_origin: bool,
        script_id: c_int,
        source_map_url: ?v8.Value,
        resource_is_opaque: bool,
        is_wasm: bool,
        is_module: bool,
    ) v8.ScriptOrigin {
        const host_defined_options = v8.PrimitiveArray.init(self.isolate, 2);
        _ = self.realm.get_root_map() catch unreachable;
        host_defined_options.set(self.isolate, 0, v8.Number.initUInt(self.isolate, JsRealm.ROOT_MAP_ID).numeric.primitive);
        host_defined_options.set(self.isolate, 1, v8.Number.initUInt(self.isolate, JsRealm.DEFAULT_RESOLVER_ID).numeric.primitive);
        const origin = v8.ScriptOrigin.init(
            resource_name,
            resource_line_offset,
            resource_column_offset,
            resource_is_shared_cross_origin,
            script_id,
            source_map_url,
            resource_is_opaque,
            is_wasm,
            is_module,
            host_defined_options.data,
        );
        return origin;
    }
};

pub const JsRealm = struct {
    pub const ROOT_MAP_ID = 0;
    pub const DEFAULT_RESOLVER_ID = 0;

    map_pool: std.heap.MemoryPool(ModuleMap),
    maps: std.AutoHashMapUnmanaged(u31, *ModuleMap),
    resolvers: std.AutoHashMapUnmanaged(u31, *Resolver),
    next_module_id: mp.ModuleId,
    modules: std.AutoHashMapUnmanaged(mp.ModuleId, *mp.Module),
    alloc: std.mem.Allocator,

    pub fn init(alloc_: std.mem.Allocator) @This() {
        return .{
            .map_pool = .empty,
            .maps = .empty,
            .resolvers = .empty,
            .modules = .empty,
            .alloc = alloc_,
            .next_module_id = 0x100,
        };
    }

    pub fn get_root_map(self: *@This()) !*ModuleMap {
        const result = try self.maps.getOrPut(self.alloc, ROOT_MAP_ID);
        if (result.found_existing) {
            return result.value_ptr.*;
        } else {
            const map = blk: {
                const map_ptr = try self.map_pool.create(self.alloc);
                map_ptr.* = .init(self);
                break :blk map_ptr;
            };
            result.value_ptr.* = map;
            return map;
        }
    }
};

const mp = @import("./map.zig");
const ModuleMap = mp.ModuleMap;
const Resolver = @import("./resolver.zig");

const std = @import("std");
const v8 = @import("../v8.zig");
const u = @import("./utils.zig");
