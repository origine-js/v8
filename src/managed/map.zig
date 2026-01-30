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
    specifiers: std.StringHashMapUnmanaged(ModuleRef),
    ref_count: rc.RcData = .{},

    pub fn init(realm: *runtime.JsRealm) @This() {
        return .{
            .realm = realm,
            .specifiers = .empty,
        };
    }

    pub fn with_capacity(realm: *runtime.JsRealm, modules_cap: usize, specifier_cap: usize) !@This() {
        var x: @This() = .init(realm);
        try x.modules.ensureTotalCapacity(realm.alloc, modules_cap);
        try x.specifiers.ensureTotalCapacity(realm.alloc, specifier_cap);
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
        self.specifiers.deinit(self.alloc);
    }

    pub fn derive(self: *@This()) !*ModuleMap {
        const map_ptr = try self.realm.map_pool.create(self.realm.alloc);
        map_ptr.* = .{
            .alloc = self.ptr.alloc,
            .specifiers = .empty,
            .modules = .empty,
            .depth = blk: {
                const next_depth, const overflow = @addWithOverflow(self.ptr.depth, 1);
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
    }

    pub fn lookup(self: *const @This(), specifier: []const u8) !?ModuleId {
        const Lookuper = struct {
            const RECURSION_LIMIT = 8;

            fn lookup(specifiers: *const std.StringHashMapUnmanaged(ModuleRef), specifier_: []const u8, depth: u16) !?ModuleId {
                if (depth > RECURSION_LIMIT) return error.RecursionLimitExceed;
                const mod_ref = specifiers.get(specifier_) orelse return null;
                switch (mod_ref) {
                    .Mod => |mod_id| return mod_id,
                    .Alias => |next| {
                        return @This().lookup(specifiers, next, depth + 1);
                    },
                }
            }
        };

        return Lookuper.lookup(&self.specifiers, specifier, 0);
    }
};

pub const std = @import("std");
const rc = @import("./rc.zig");
const runtime = @import("./runtime.zig");
const v8 = @import("../v8.zig");
