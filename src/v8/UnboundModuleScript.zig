const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const UnboundModuleScript = extern struct {
    data: v8.Data,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .data = v8.Data.from_opaque(o) orelse return null };
    }

    pub fn createCodeCache(unbound_module_script: v8.UnboundModuleScript) ?v8.ScriptCompiler.CachedData {
        return .{ .handle = e.v8__UnboundModuleScript__CreateCodeCache(unbound_module_script) orelse return null };
    }

    pub fn getSourceMappingURL(unbound_module_script: v8.UnboundModuleScript) ?v8.Value {
        return v8.Value.from_opaque(e.v8__UnboundModuleScript__GetSourceMappingURL(unbound_module_script));
    }

    pub fn getSourceURL(unbound_module_script: v8.UnboundModuleScript) ?v8.Value {
        return v8.Value.from_opaque(e.v8__UnboundModuleScript__GetSourceURL(unbound_module_script));
    }
};
