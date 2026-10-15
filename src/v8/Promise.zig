const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Context = v8.Context;
const MaybeHandle = v8.MaybeHandle;
const Value = v8.Value;
const Object = v8.Object;

pub const Promise = extern struct {
    object: Object,

    pub const PromiseState = enum(c_int) { Pending, Fulfilled, Rejected };

    pub const Resolver = extern struct {
        object: Object,

        pub fn from_opaque(o: MaybeHandle) ?@This() {
            return .{ .object = Object.from_opaque(o) orelse return null };
        }

        pub fn init(context: Context) ?@This() {
            return .from_opaque(e.v8__Promise__Resolver__New(context));
        }

        pub fn getPromise(self: @This()) Promise {
            return Promise.from_opaque(e.v8__Promise__Resolver__GetPromise(self)).?;
        }

        pub fn resolve(self: @This(), context: Context, value: Value) ?bool {
            return e.v8__Promise__Resolver__Resolve(self, context, value).as_optional();
        }

        pub fn reject(self: @This(), context: Context, value: Value) ?bool {
            return e.v8__Promise__Resolver__Reject(self, context, value).as_optional();
        }
    };

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .object = Object.from_opaque(o) orelse return null };
    }

    pub fn result(self: @This()) Value {
        return Value.from_opaque(e.v8__Promise__Result(self)).?;
    }

    pub fn state(self: @This()) PromiseState {
        return e.v8__Promise__State(self);
    }

    /// Borrows `self` for this call; a later rejection is then not reported as unhandled. Retains nothing.
    pub fn markAsHandled(self: v8.Promise) void {
        e.v8__Promise__MarkAsHandled(self);
    }

    pub fn hasHandler(self: v8.Promise) bool {
        return e.v8__Promise__HasHandler(self);
    }

    pub fn @"catch"(self: v8.Promise, context: v8.Context, handler: v8.Function) ?v8.Promise {
        return v8.Promise.from_opaque(e.v8__Promise__Catch(self, context, handler));
    }

    pub fn then(self: v8.Promise, context: v8.Context, handler: v8.Function) ?v8.Promise {
        return v8.Promise.from_opaque(e.v8__Promise__Then(self, context, handler));
    }

    pub fn then2(self: v8.Promise, context: v8.Context, on_fulfilled: v8.Function, on_rejected: v8.Function) ?v8.Promise {
        return v8.Promise.from_opaque(e.v8__Promise__Then2(self, context, on_fulfilled, on_rejected));
    }
};
