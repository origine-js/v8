const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const RegExp = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    /// Mirrors `v8::RegExp::Flags`; all clear is `kNone`.
    pub const Flags = packed struct(u32) {
        Global: bool = false,
        IgnoreCase: bool = false,
        Multiline: bool = false,
        Sticky: bool = false,
        Unicode: bool = false,
        DotAll: bool = false,
        Linear: bool = false,
        HasIndices: bool = false,
        UnicodeSets: bool = false,
        _unused: u23 = 0,
    };

    pub fn init(context: v8.Context, pattern: v8.String, flags: Flags) ?v8.RegExp {
        return v8.RegExp.from_opaque(e.v8__RegExp__New(context, pattern, flags));
    }

    pub fn exec(self: v8.RegExp, context: v8.Context, subject: v8.String) ?v8.Object {
        return v8.Object.from_opaque(e.v8__RegExp__Exec(self, context, subject));
    }

    pub fn getSource(self: v8.RegExp) ?v8.String {
        return v8.String.from_opaque(e.v8__RegExp__GetSource(self));
    }
};
