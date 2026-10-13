const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const ExternalOneByteStringResource = extern struct {
    pub const Opaque = opaque {};
    handle: *Opaque,

    pub fn data(self: v8.ExternalOneByteStringResource) ?[*]const u8 {
        return e.v8__ExternalOneByteStringResource__data(self.handle);
    }

    pub fn length(self: v8.ExternalOneByteStringResource) usize {
        return e.v8__ExternalOneByteStringResource__length(self.handle);
    }
};
