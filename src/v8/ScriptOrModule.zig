const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const ScriptOrModule = extern struct {
    data: v8.Data,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .data = v8.Data.from_opaque(o) orelse return null };
    }

    pub fn getResourceName(self: v8.ScriptOrModule) ?v8.Value {
        return v8.Value.from_opaque(e.v8__ScriptOrModule__GetResourceName(self));
    }

    pub fn hostDefinedOptions(self: v8.ScriptOrModule) ?v8.Data {
        return v8.Data.from_opaque(e.v8__ScriptOrModule__HostDefinedOptions(self));
    }
};
