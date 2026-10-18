const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const MaybeHandle = v8.MaybeHandle;
const Value = v8.Value;

pub const Primitive = extern struct {
    value: Value,

    /// The JavaScript `null` value.
    pub fn initNull(isolate: Isolate) Primitive {
        return from_opaque(e.v8__Null(isolate.handle)).?;
    }

    /// The JavaScript `undefined` value.
    pub fn initUndefined(isolate: Isolate) Primitive {
        return from_opaque(e.v8__Undefined(isolate.handle)).?;
    }

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .value = Value.from_opaque(o) orelse return null,
        };
    }
};
