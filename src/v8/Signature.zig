const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const Signature = extern struct {
    pub const Opaque = opaque {};

    handle: *Opaque,

    pub fn init(isolate: v8.Isolate, templ: ?v8.FunctionTemplate) ?v8.Signature {
        return v8.Signature.from_opaque(e.v8__Signature__New(isolate.handle, if (templ) |v| v8.support.rawHandle(v) else null));
    }
    pub fn from_opaque(o: ?*const Opaque) ?@This() {
        return .{ .handle = @constCast(o orelse return null) };
    }
};
