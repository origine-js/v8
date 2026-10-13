pub const Specifier = []const u8;

pub const ModuleRequest = struct {
    specifier: Specifier,
    resolved_module: ModuleId,
};

pub const ModuleId = u31;

pub const ModuleType = enum {
    module,
    wasm,
    text,
    json,
    bytes,
};

pub const Module = struct {
    id: ModuleId,
    module: v8.Global.Of(v8.Module),
    requests: std.ArrayList(*ModuleRequest),
    phase: v8.ModuleImportPhase,
    type: ModuleType,
};

pub const ModuleRef = union(enum) {
    Mod: ModuleId,
    Alias: Specifier,
};

pub const ModuleMap = struct {
    realm: *runtime.JsRealm,
    depth: u8 = 0,
    parent: ?*ModuleMap = null,
    mapper: std.StringHashMapUnmanaged(ModuleRef),
    paths: std.ArrayList([]const u8),
    ref_count: rc.RcData = .{},

    pub fn init(realm: *runtime.JsRealm) @This() {
        return .{
            .realm = realm,
            .mapper = .empty,
            .paths = .empty,
        };
    }

    pub fn with_capacity(realm: *runtime.JsRealm, specifier_cap: usize) !@This() {
        var x: @This() = .init(realm);
        try x.mapper.ensureTotalCapacity(realm.alloc, specifier_cap);
        return x;
    }

    pub fn ref(self: *@This()) void {
        self.ref_count.inc();
    }

    pub fn deref(self: *@This()) void {
        if (self.ref_count.dec()) {
            const state = &self.realm;
            self.deinit();
            state.map_pool.destroy(self);
        }
    }

    pub fn deinit(self: *@This()) void {
        if (self.parent) |p| {
            p.deref();
        }
        self.modules.deinit(self.alloc);
        self.mapper.deinit(self.alloc);
    }

    pub fn derive(self: *@This()) !*ModuleMap {
        const map_ptr = try self.realm.map_pool.create(self.realm.alloc);
        map_ptr.* = .{
            .alloc = self.realm.alloc,
            .mapper = .empty,
            .depth = blk: {
                const next_depth, const overflow = @addWithOverflow(self.depth, 1);
                if (overflow) {
                    return error.DepthLimitExceed;
                }
                break :blk next_depth;
            },
            .parent = blk: {
                self.ref();
                break :blk self;
            },
        };
        return map_ptr;
    }

    pub fn lookup(self: *const @This(), specifier: []const u8) !?ModuleId {
        const Lookuper = struct {
            const RECURSION_LIMIT = 16;

            fn lookup(map: *const ModuleMap, specifier_: []const u8, depth: u16) !?ModuleId {
                if (depth > RECURSION_LIMIT) return error.RecursionLimitExceed;
                const mod_ref = map.mapper.get(specifier_) orelse return {
                    if (map.parent) |parent| {
                        return @This().lookup(parent, specifier_, depth + 1);
                    }
                    return null;
                };
                switch (mod_ref) {
                    .Mod => |mod_id| return mod_id,
                    .Alias => |next| {
                        return @This().lookup(map, next, depth + 1);
                    },
                }
            }
        };

        return Lookuper.lookup(self, specifier, 0);
    }
};

pub const std = @import("std");
const rc = @import("./rc.zig");
const runtime = @import("./runtime.zig");
const v8 = @import("../v8.zig");
