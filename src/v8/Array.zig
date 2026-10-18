const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const MaybeHandle = v8.MaybeHandle;
const Value = v8.Value;
const Object = v8.Object;

pub const Array = extern struct {
    object: Object,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .object = Object.from_opaque(o) orelse return null,
        };
    }

    pub fn init(isolate: Isolate, length: c_int) @This() {
        return @This().from_opaque(e.v8__Array__New(isolate.handle, length)).?;
    }

    pub fn with_elements(isolate: Isolate, elements: []const Value) ?@This() {
        return @This().from_opaque(e.v8__Array__New_with_elements(isolate.handle, @ptrCast(elements.ptr), elements.len));
    }

    pub fn len(self: @This()) u32 {
        return e.v8__Array__Length(self);
    }
};
