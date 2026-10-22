const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const DataView = extern struct {
    arrayBufferView: v8.ArrayBufferView,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .arrayBufferView = v8.ArrayBufferView.from_opaque(o) orelse return null };
    }

    /// Borrows a buffer on its entered isolate thread; returns a local view in the
    /// current handle scope, or null with the pending V8 exception on failure.
    pub fn init(ab: anytype, offset: usize, length: usize) ?v8.DataView {
        return v8.DataView.from_opaque(e.v8__DataView__New(v8.ArrayBufferBase.fromBuffer(ab), offset, length));
    }
};
