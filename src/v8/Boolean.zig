const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const MaybeHandle = v8.MaybeHandle;
const Isolate = v8.Isolate;
const Context = v8.Context;
const String = v8.String;
const Value = v8.Value;
const Primitive = v8.Primitive;

pub const Boolean = extern struct {
    primitive: Primitive,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .primitive = Primitive.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, v: bool) @This() {
        return from_opaque(e.v8__Boolean__New(isolate.handle, v)).?;
    }
};
