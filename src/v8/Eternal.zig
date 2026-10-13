const binding = @import("../binding.zig");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const Eternal = extern struct {
    storage: [binding.sizes.Eternal_Data]u8 align(@alignOf(usize)),
    pub const Data = @This();

    pub fn init(buf: *v8.Eternal) void {
        e.v8__Eternal__CONSTRUCT(buf);
    }

    pub fn deinit(self: *v8.Eternal) void {
        e.v8__Eternal__DESTRUCT(self);
    }

    pub fn clear(self: *v8.Eternal) void {
        e.v8__Eternal__Clear(self);
    }

    pub fn isEmpty(self: *v8.Eternal) bool {
        return e.v8__Eternal__IsEmpty(self);
    }

    pub fn set(self: *v8.Eternal, isolate: v8.Isolate, value: ?v8.Data) void {
        e.v8__Eternal__Set(self, isolate.handle, if (value) |v| v8.support.rawHandle(v) else null);
    }

    pub fn get(self: *v8.Eternal, isolate: v8.Isolate) ?v8.Data {
        return v8.Data.from_opaque(e.v8__Eternal__Get(self, isolate.handle));
    }
};
