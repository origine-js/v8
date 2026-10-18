//! Thread-safe Zig allocator backed by the pinned, statically linked mimalloc.
//! Binds the mi_* allocation, heap, collection and statistics APIs plus a `std.mem.Allocator`.
//! Does not replace libc malloc/free by itself; V8's `base::Malloc` family is routed here by
//! build-tools/patches/v8/0004-mimalloc.patch whenever this archive is linked.
const std = @import("std");

// ---- Raw mi_* bindings. Pointers returned by any allocating function are owned by
// the caller and released with mi_free (or the matching heap-free). ----

/// Returns uninitialized caller-owned storage of `size` bytes, or null on failure.
pub extern fn mi_malloc(size: usize) ?*anyopaque;
/// Returns zeroed caller-owned storage for `count * size` bytes, or null on failure or overflow.
pub extern fn mi_calloc(count: usize, size: usize) ?*anyopaque;
/// Returns zeroed caller-owned storage of `size` bytes, or null on failure.
pub extern fn mi_zalloc(size: usize) ?*anyopaque;
/// Consumes `p` (null or mimalloc-owned) and returns resized storage; on null result `p` stays valid.
pub extern fn mi_realloc(p: ?*anyopaque, newsize: usize) ?*anyopaque;
/// Like mi_realloc, but the result is aligned to `alignment` (a power of two).
pub extern fn mi_realloc_aligned(p: ?*anyopaque, newsize: usize, alignment: usize) ?*anyopaque;
/// Returns caller-owned storage aligned to `alignment` (a power of two), or null on failure.
pub extern fn mi_malloc_aligned(size: usize, alignment: usize) ?*anyopaque;
/// Consumes a mimalloc allocation (or null); the pointer is invalid after return.
pub extern fn mi_free(ptr: ?*anyopaque) void;
/// Borrows `ptr` through the call; returns its usable byte capacity (0 for null).
pub extern fn mi_usable_size(ptr: ?*const anyopaque) usize;
/// Accepts no resources; returns the size mimalloc would actually reserve for `size`.
pub extern fn mi_good_size(size: usize) usize;
/// Borrows the NUL-terminated `s` for the call; returns a caller-owned copy released with mi_free.
pub extern fn mi_strdup(s: [*:0]const u8) ?[*:0]u8;
/// Borrows `p` for the call; reports whether it lies in a mimalloc-managed region.
pub extern fn mi_is_in_heap_region(p: ?*const anyopaque) bool;
/// Returns every free page to the OS when `force`; touches only allocator state.
pub extern fn mi_collect(force: bool) void;
/// Accepts no resources; returns the linked mimalloc version number.
pub extern fn mi_version() c_int;
/// Flushes the calling thread's cached state; call before a thread exits. Retains nothing.
pub extern fn mi_thread_done() void;
/// Writes allocator statistics to stderr; retains nothing.
pub extern fn mi_stats_print(out: ?*anyopaque) void;
/// Writes process counters through the non-null out-pointers; retains nothing.
pub extern fn mi_process_info(
    elapsed_msecs: ?*usize,
    user_msecs: ?*usize,
    system_msecs: ?*usize,
    current_rss: ?*usize,
    peak_rss: ?*usize,
    current_commit: ?*usize,
    peak_commit: ?*usize,
    page_faults: ?*usize,
) void;

/// Opaque mimalloc heap; created by mi_heap_new and consumed by mi_heap_destroy/delete.
pub const Heap = opaque {
    /// Returns a caller-owned heap, or null on failure; delete/destroy it on the
    /// creating thread. Retains no input resources.
    extern fn mi_heap_new() ?*Heap;
    /// Consumes the heap on its creating thread; migrates live allocations to
    /// the default heap. Blocks remain caller-owned and must be freed with mi_free.
    extern fn mi_heap_delete(heap: *Heap) void;
    /// Consumes the heap and all its blocks on the creating thread; invalidates
    /// every pointer allocated through it, including self.
    extern fn mi_heap_destroy(heap: *Heap) void;
    /// Borrows heap through allocation on its creating thread. Returns caller-owned
    /// aligned storage, released with mi_free or heap destruction; null retains nothing.
    extern fn mi_heap_malloc_aligned(heap: *Heap, size: usize, alignment: usize) ?*anyopaque;
    /// Borrows heap on its creating thread and consumes p only on success.
    /// Returns caller-owned aligned storage released with mi_free/heap destruction;
    /// null leaves the original allocation valid and caller-owned.
    extern fn mi_heap_realloc_aligned(heap: *Heap, p: ?*anyopaque, newsize: usize, alignment: usize) ?*anyopaque;

    /// Creates a caller-owned heap, or null on failure. Allocate only from the creating
    /// thread; blocks may be freed from any thread. Release with `destroy` or `delete`.
    pub fn create() ?*Heap {
        return mi_heap_new();
    }

    /// Consumes the heap and frees every block allocated from it, live or not.
    /// No block from this heap may be used afterwards; `self` is invalid after return.
    pub fn destroy(self: *Heap) void {
        mi_heap_destroy(self);
    }

    /// Consumes the heap but migrates its live blocks to the default heap, so they stay valid
    /// and must still be freed individually. `self` is invalid after return.
    pub fn delete(self: *Heap) void {
        mi_heap_delete(self);
    }

    /// Borrows self; the returned allocator aliases it and is valid until destroy/delete.
    /// Allocation must stay on the creating thread. Freed blocks may be released anywhere.
    /// destroy() reclaims blocks wholesale, so individual frees are optional.
    pub fn allocator(self: *Heap) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &heap_vtable };
    }
};

const heap_vtable: std.mem.Allocator.VTable = .{ .alloc = heapAlloc, .resize = resize, .remap = heapRemap, .free = free };

/// Allocates from the Heap in `ctx` (borrowed, not retained); the caller owns the block.
fn heapAlloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    const heap: *Heap = @ptrCast(ctx);
    return @ptrCast(Heap.mi_heap_malloc_aligned(heap, len, alignment.toByteUnits()) orelse return null);
}

/// Borrows `memory`; resizes in place or moves within the Heap in `ctx`. On null the
/// original block is untouched and still owned by the caller; on success the old pointer is invalid.
fn heapRemap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
    const heap: *Heap = @ptrCast(ctx);
    return @ptrCast(Heap.mi_heap_realloc_aligned(heap, memory.ptr, new_len, alignment.toByteUnits()) orelse return null);
}

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

/// Borrows mimalloc-owned memory. Returns the same pointer when capacity suffices, else a
/// moved block (old pointer invalidated, contents preserved). On null the original block
/// is unchanged and still owned by the caller.
fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
    if (resize(ctx, memory, alignment, new_len, ra)) return memory.ptr;
    return @ptrCast(mi_realloc_aligned(memory.ptr, new_len, alignment.toByteUnits()) orelse return null);
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

test "mimalloc: raw API, remap and heap allocator" {
    const p = mi_zalloc(100) orelse return error.OutOfMemory;
    try std.testing.expect(mi_usable_size(p) >= 100);
    try std.testing.expect(mi_good_size(100) >= 100);
    const q = mi_realloc(p, 10000) orelse return error.OutOfMemory;
    try std.testing.expectEqual(@as(u8, 0), @as(*u8, @ptrCast(q)).*);
    mi_free(q);
    const dup = mi_strdup("abc") orelse return error.OutOfMemory;
    try std.testing.expectEqualStrings("abc", std.mem.span(dup));
    mi_free(dup);

    const heap = Heap.create() orelse return error.OutOfMemory;
    defer heap.destroy();
    var list: std.ArrayList(u64) = .empty;
    for (0..1000) |i| try list.append(heap.allocator(), i);
    try std.testing.expectEqual(@as(u64, 999), list.items[999]);
    mi_collect(false);
}
