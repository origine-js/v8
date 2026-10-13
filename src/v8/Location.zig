const v8Binding = @import("../binding.zig");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const Location = extern struct {
    storage: [v8Binding.sizes.Location]u8 align(@alignOf(c_int)),

    pub fn getLineNumber(self: *v8.Location) c_int {
        return e.v8__Location__GetLineNumber(self);
    }

    pub fn getColumnNumber(self: *v8.Location) c_int {
        return e.v8__Location__GetColumnNumber(self);
    }
};
