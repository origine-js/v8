const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const Proxy = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn init(context: v8.Context, target: v8.Object, handler: v8.Object) ?v8.Proxy {
        return v8.Proxy.from_opaque(e.v8__Proxy__New(context, target, handler));
    }

    pub fn getHandler(self: v8.Proxy) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Proxy__GetHandler(self));
    }

    pub fn getTarget(self: v8.Proxy) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Proxy__GetTarget(self));
    }

    pub fn isRevoked(self: v8.Proxy) bool {
        return e.v8__Proxy__IsRevoked(self);
    }

    pub fn revoke(self: v8.Proxy) void {
        e.v8__Proxy__Revoke(self);
    }
};
