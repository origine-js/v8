//! Thread-safe Zig allocator backed by the pinned, statically linked mimalloc.
//! Uses mi_* APIs only; does not replace libc malloc/free or require owned heap state.
const std = @import("std");

/// Returns mimalloc-owned aligned storage, or null on failure; release with mi_free.
extern fn mi_malloc_aligned(size: usize, alignment: usize) ?*anyopaque;
/// Borrows an allocation pointer through return; returns its usable byte capacity.
extern fn mi_usable_size(ptr: *const anyopaque) usize;
/// Consumes a mimalloc allocation. The pointer is invalid after return.
extern fn mi_free(ptr: ?*anyopaque) void;
/// Accepts no resources; returns the linked mimalloc version number.
pub extern fn mi_version() c_int;

/// Stateless process-lifetime allocator. Allocations may be freed on other threads.
/// Caller owns returned storage and releases it through this allocator. No deinit.
pub const allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free },
};

/// Allocates caller-owned aligned storage via mimalloc; null transfers no ownership.
/// Context and return address are unused; no caller state is retained.
fn alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    return @ptrCast(mi_malloc_aligned(len, alignment.toByteUnits()) orelse return null);
}

/// Borrows mimalloc-owned memory through return. On true its capacity covers new_len;
/// on false the allocation is unchanged. Caller retains ownership in either case.
fn resize(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    return new_len <= mi_usable_size(memory.ptr);
}

/// Borrows mimalloc-owned memory. Returns the same pointer when capacity suffices;
/// null leaves ownership and contents unchanged for the caller's realloc fallback.
fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
    return if (resize(ctx, memory, alignment, new_len, ra)) memory.ptr else null;
}

/// Consumes a block allocated by this allocator. Does not retain caller state.
fn free(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    mi_free(memory.ptr);
}

test "mimalloc: aligned allocation, realloc preservation and zero-size allocation" {
    try std.testing.expectEqual(@as(c_int, 30503), mi_version());
    var memory = try allocator.alignedAlloc(u8, .fromByteUnits(4096), 31);
    defer allocator.free(memory);
    @memset(memory, 0x5a);
    memory = try allocator.realloc(memory, 1024 * 1024);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(memory.ptr) % 4096);
    const expected: [31]u8 = @splat(0x5a);
    try std.testing.expectEqualSlices(u8, &expected, memory[0..31]);
    const empty = try allocator.alloc(u8, 0);
    defer allocator.free(empty);
}

/// Consumes caller-owned memory on the spawned thread; retains no resources on return.
fn freeOnWorker(memory: []u8) void {
    allocator.free(memory);
}

test "mimalloc: blocks can be freed from a different thread" {
    const memory = try allocator.alloc(u8, 4096);
    @memset(memory, 0x5a);
    const worker = std.Thread.spawn(.{}, freeOnWorker, .{memory}) catch |err| {
        allocator.free(memory);
        return err;
    };
    worker.join();
}
