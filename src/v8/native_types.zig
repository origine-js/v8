//! Value layouts and callback tables used by the C++ shim.
const e = @import("../externs.gen.zig");

const v8 = @import("../v8.zig");
const binding = @import("../binding.zig");

pub const HeapSpaceStatistics = extern struct {
    space_name: ?[*:0]const u8,
    space_size: usize,
    space_used_size: usize,
    space_available_size: usize,
    physical_space_size: usize,
    comptime {
        if (@sizeOf(@This()) != binding.sizes.HeapSpaceStatistics) @compileError("HeapSpaceStatistics layout mismatch");
    }
};

/// Keep the table and its state alive until the allocator is destroyed.
pub const ZigAllocatorTable = extern struct {
    allocate_zeroed: *const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    allocate: *const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    free: *const fn (?*anyopaque, ?*anyopaque, usize) callconv(.c) void,
    deinit: *const fn (?*anyopaque) callconv(.c) void,
};

pub const StalledTopLevelAwaitMessage = extern struct {
    module: v8.MaybeHandle,
    message: ?*const v8.Message.Opaque,
};

/// Owns a shared backing-store reference returned by getBackingStore. Do not copy;
/// pass its address to buffer constructors and call deinit once.
pub const SharedBackingStore = extern struct {
    a: ?*anyopaque,
    b: ?*anyopaque,
    pub fn deinit(self: *@This()) void {
        e.v8__BackingStore__shared_ptr_DESTRUCT(self);
    }
};
