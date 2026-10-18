const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Data = v8.Data;

pub const FixedArray = extern struct {
    data: Data,

    pub fn len(self: @This()) c_int {
        return e.v8__FixedArray__Length(self);
    }

    pub fn get(self: @This(), idx: c_int) ?Data {
        return .from_opaque(e.v8__FixedArray__Get(self, idx));
    }
    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .data = v8.Data.from_opaque(o) orelse return null };
    }
};
