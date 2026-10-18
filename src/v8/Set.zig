const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const Set = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: v8.Isolate) ?v8.Set {
        return v8.Set.from_opaque(e.v8__Set__New(isolate.handle));
    }

    pub fn size(self: v8.Set) usize {
        return e.v8__Set__Size(self);
    }

    pub fn clear(self: v8.Set) void {
        e.v8__Set__Clear(self);
    }

    pub fn add(self: v8.Set, context: v8.Context, key: v8.Value) ?v8.Set {
        return v8.Set.from_opaque(e.v8__Set__Add(self, context, key));
    }

    pub fn has(self: v8.Set, context: v8.Context, key: v8.Value) ?bool {
        return e.v8__Set__Has(self, context, key).as_optional();
    }

    pub fn delete(self: v8.Set, context: v8.Context, key: v8.Value) ?bool {
        return e.v8__Set__Delete(self, context, key).as_optional();
    }

    pub fn asArray(self: v8.Set) ?v8.Array {
        return v8.Array.from_opaque(e.v8__Set__As__Array(self));
    }
};
