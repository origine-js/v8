const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const PropertyAttribute = v8.PropertyAttribute;
const MaybeHandle = v8.MaybeHandle;
const Data = v8.Data;
const Name = v8.Name;

pub const Template = extern struct {
    data: Data,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .data = Data.from_opaque(o) orelse return null };
    }

    pub fn set(self: @This(), key: Name, value: Data, attr: PropertyAttribute) void {
        e.v8__Template__Set(self, key, value, attr);
    }

    pub fn setIntrinsicDataProperty(self: v8.Template, key: v8.Name, intrinsic: u32, attr: v8.PropertyAttribute) void {
        e.v8__Template__SetIntrinsicDataProperty(self, key, intrinsic, attr);
    }
};
