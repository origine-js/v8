const v8Binding = @import("../generated/binding.zig");
const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const PromiseRejectMessage = extern struct {
    storage: [v8Binding.sizes.PromiseRejectMessage]u8 align(@alignOf(usize)),

    pub fn getEvent(self: *const v8.PromiseRejectMessage) u32 {
        return e.v8__PromiseRejectMessage__GetEvent(self);
    }

    pub fn getPromise(self: *const v8.PromiseRejectMessage) ?v8.Promise {
        return v8.Promise.from_opaque(e.v8__PromiseRejectMessage__GetPromise(self));
    }

    pub fn getValue(self: *const v8.PromiseRejectMessage) ?v8.Value {
        return v8.Value.from_opaque(e.v8__PromiseRejectMessage__GetValue(self));
    }
};
