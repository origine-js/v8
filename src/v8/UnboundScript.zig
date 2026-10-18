const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const UnboundScript = extern struct {
    data: v8.Data,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .data = v8.Data.from_opaque(o) orelse return null };
    }

    /// Borrows `unbound_script` for this call; returns V8's script id. Retains nothing.
    pub fn scriptId(unbound_script: v8.UnboundScript) c_int {
        return e.v8__UnboundScript__ScriptId(unbound_script);
    }

    pub fn bindToCurrentContext(unbound_script: v8.UnboundScript) ?v8.Script {
        return v8.Script.from_opaque(e.v8__UnboundScript__BindToCurrentContext(unbound_script));
    }

    pub fn createCodeCache(unbound_script: v8.UnboundScript) ?v8.ScriptCompiler.CachedData {
        return .{ .handle = e.v8__UnboundScript__CreateCodeCache(unbound_script) orelse return null };
    }

    pub fn getSourceMappingURL(unbound_script: v8.UnboundScript) ?v8.Value {
        return v8.Value.from_opaque(e.v8__UnboundScript__GetSourceMappingURL(unbound_script));
    }

    pub fn getSourceURL(unbound_script: v8.UnboundScript) ?v8.Value {
        return v8.Value.from_opaque(e.v8__UnboundScript__GetSourceURL(unbound_script));
    }
};
