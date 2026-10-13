const binding = @import("../binding.zig");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const TracedReference = extern struct {
    storage: [binding.sizes.TracedReference_Data]u8 align(@alignOf(usize)),
    pub const Data = @This();

    pub fn init(buf: *v8.TracedReference) void {
        e.v8__TracedReference__CONSTRUCT(buf);
    }

    pub fn deinit(self: *v8.TracedReference) void {
        e.v8__TracedReference__DESTRUCT(self);
    }

    pub fn reset(self: *v8.TracedReference, isolate: v8.Isolate, other: ?v8.Data) void {
        e.v8__TracedReference__Reset(self, isolate.handle, if (other) |v| v8.support.rawHandle(v) else null);
    }

    pub fn get(self: *v8.TracedReference, isolate: v8.Isolate) ?v8.Data {
        return v8.Data.from_opaque(e.v8__TracedReference__Get(self, isolate.handle));
    }
};
