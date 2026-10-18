const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const MaybeHandle = v8.MaybeHandle;
const Primitive = v8.Primitive;

pub const Numeric = extern struct {
    primitive: Primitive,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .primitive = Primitive.from_opaque(o) orelse return null };
    }
};
