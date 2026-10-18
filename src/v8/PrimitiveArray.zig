const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const MaybeHandle = v8.MaybeHandle;
const Data = v8.Data;
const Primitive = v8.Primitive;

pub const PrimitiveArray = extern struct {
    data: Data,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .data = Data.from_opaque(o) orelse return null,
        };
    }

    pub fn init(isolate: Isolate, length_arg: c_int) @This() {
        return @This().from_opaque(e.v8__PrimitiveArray__New(isolate.handle, length_arg)).?;
    }

    pub fn set(self: @This(), isolate: Isolate, index: c_int, primitive: Primitive) void {
        e.v8__PrimitiveArray__Set(self, isolate.handle, index, primitive);
    }

    pub fn get(self: @This(), isolate: Isolate, index: c_int) Primitive {
        return Primitive.from_opaque(e.v8__PrimitiveArray__Get(self, isolate.handle, index)).?;
    }

    pub fn length(self: v8.PrimitiveArray) c_int {
        return e.v8__PrimitiveArray__Length(self);
    }
};
