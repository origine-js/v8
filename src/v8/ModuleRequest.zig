const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const ModuleRequest = extern struct {
    data: v8.Data,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .data = v8.Data.from_opaque(o) orelse return null };
    }

    pub fn getSpecifier(self: v8.ModuleRequest) ?v8.String {
        return v8.String.from_opaque(e.v8__ModuleRequest__GetSpecifier(self));
    }

    pub fn getPhase(self: v8.ModuleRequest) v8.ModuleImportPhase {
        return e.v8__ModuleRequest__GetPhase(self);
    }

    pub fn getSourceOffset(self: v8.ModuleRequest) c_int {
        return e.v8__ModuleRequest__GetSourceOffset(self);
    }

    pub fn getImportAttributes(self: v8.ModuleRequest) ?v8.FixedArray {
        return v8.FixedArray.from_opaque(e.v8__ModuleRequest__GetImportAttributes(self));
    }
};
