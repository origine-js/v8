const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const MaybeHandle = v8.MaybeHandle;
const Isolate = v8.Isolate;
const Context = v8.Context;
const String = v8.String;
const Value = v8.Value;
const Data = v8.Data;

pub const Private = extern struct {
    data: Data,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .data = Data.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, n: ?String) @This() {
        return from_opaque(e.v8__Private__New(isolate.handle, nameHandle(n))).?;
    }

    pub fn forApi(isolate: Isolate, n: String) @This() {
        return from_opaque(e.v8__Private__ForApi(isolate.handle, nameHandle(n))).?;
    }

    pub fn name(self: @This()) Value {
        return Value.from_opaque(e.v8__Private__Name(self)).?;
    }

    fn nameHandle(s: ?String) MaybeHandle {
        return (s orelse return null).name.primitive.value.data.handle;
    }
};
