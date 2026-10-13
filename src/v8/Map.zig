const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const Map = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: v8.Isolate) ?v8.Map {
        return v8.Map.from_opaque(e.v8__Map__New(isolate.handle));
    }

    pub fn size(self: v8.Map) usize {
        return e.v8__Map__Size(self);
    }

    pub fn clear(self: v8.Map) void {
        e.v8__Map__Clear(self);
    }

    pub fn get(self: v8.Map, context: v8.Context, key: v8.Value) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Map__Get(self, context, key));
    }

    pub fn set(self: v8.Map, context: v8.Context, key: v8.Value, value: v8.Value) ?v8.Map {
        return v8.Map.from_opaque(e.v8__Map__Set(self, context, key, value));
    }

    pub fn has(self: v8.Map, context: v8.Context, key: v8.Value) ?bool {
        return e.v8__Map__Has(self, context, key).as_optional();
    }

    pub fn delete(self: v8.Map, context: v8.Context, key: v8.Value) ?bool {
        return e.v8__Map__Delete(self, context, key).as_optional();
    }

    pub fn asArray(self: v8.Map) ?v8.Array {
        return v8.Array.from_opaque(e.v8__Map__As__Array(self));
    }
};
