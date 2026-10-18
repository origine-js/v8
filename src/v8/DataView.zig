const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const DataView = extern struct {
    arrayBufferView: v8.ArrayBufferView,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .arrayBufferView = v8.ArrayBufferView.from_opaque(o) orelse return null };
    }

    pub fn init(ab: v8.ArrayBuffer, offset: usize, length: usize) ?v8.DataView {
        return v8.DataView.from_opaque(e.v8__DataView__New(ab, offset, length));
    }
};
