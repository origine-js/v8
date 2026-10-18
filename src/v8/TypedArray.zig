const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const TypedArray = extern struct {
    arrayBufferView: v8.ArrayBufferView,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .arrayBufferView = v8.ArrayBufferView.from_opaque(o) orelse return null };
    }

    pub fn length(self: v8.TypedArray) usize {
        return e.v8__TypedArray__Length(v8.support.rawHandle(self));
    }
};
