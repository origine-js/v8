const e = @import("../generated/externs.gen.zig");
const std = @import("std");
const v8 = @import("../v8.zig");
const mi = @import("@mimalloc");
const Object = v8.Object;

pub const ArrayBuffer = extern struct {
    object: Object,

    pub const Allocator = extern struct {
        pub const Opaque = opaque {};

        handle: *Opaque,

        /// Returns an owning native allocator. Deinit only after all isolates and
        /// backing stores using it have been released; no host state is retained.
        pub fn initDefault() @This() {
            return .{
                .handle = e.v8__ArrayBuffer__Allocator__NewDefaultAllocator().?,
            };
        }

        /// Consumes this allocator and any owned adapter state. All isolates and
        /// backing stores using it must already be released. Do not copy/deinit twice.
        pub fn deinit(self: @This()) void {
            e.v8__ArrayBuffer__Allocator__DELETE(self.handle);
        }

        /// Creates an owning V8 backing-store adapter. Copies alloc into stable
        /// adapter-owned storage allocated through alloc. Its state must be thread-safe
        /// and stay alive until this allocator and every backing store are released.
        /// Call deinit once after all users. On failure no allocations are retained.
        /// Rejects V8 sandbox builds; ordinary allocators cannot supply sandbox memory (use
        /// `fromSandbox`).
        /// Does not redirect V8 GC/code pages, native malloc/new, or host allocations.
        pub fn fromZig(alloc: std.mem.Allocator) !@This() {
            if (v8.V8.isSandboxEnabled()) return error.UnsupportedSandboxAllocator;
            const state = try alloc.create(ZigState);
            errdefer alloc.destroy(state);
            state.* = .{ .alloc = alloc };
            return newZigAllocator(state, &ZigState.table) orelse error.OutOfMemory;
        }

        /// Creates an owning allocator whose backing stores live in the V8 sandbox, the only
        /// place a sandboxed V8 accepts them: a mimalloc heap over an arena of sandbox pages,
        /// with stores over 16 MiB (more than an arena block can hold) in pages of their own.
        /// Stores are zero-filled on request, 16-byte aligned, and may be allocated and freed
        /// from any thread. `deinit` destroys the heap and unloads the arena (mimalloc keeps the
        /// arena's metadata inside the sandbox) before returning the pages, so it must run before
        /// `V8.dispose`, after all isolates and backing stores using it (a store that outlives its
        /// isolate keeps the allocator alive until the store is freed). V8 must be initialized.
        /// Errors: SandboxDisabled without a sandbox, OutOfMemory otherwise.
        pub fn fromSandbox() !@This() {
            if (!v8.V8.isSandboxEnabled()) return error.SandboxDisabled;
            const state = try SandboxState.create();
            errdefer state.destroy();
            return newZigAllocator(state, &SandboxState.table) orelse error.OutOfMemory;
        }

        const SandboxState = struct {
            heap: *mi.Heap,
            arena: mi.Arena.Id,
            base: [*]u8,
            size: usize,

            const alignment: std.mem.Alignment = .@"16";
            /// Address space (not memory) of the arena: the most one mimalloc arena can span.
            const arena_bytes = 8 << 30;
            const arena_alignment = 4 << 20;
            const min_arena_bytes = 256 << 20;
            /// mimalloc serves arena blocks only up to 32 MiB, so bigger stores take whole sandbox
            /// pages like V8's own allocator. `free` gets the same length, so it can tell.
            const direct_threshold = 16 << 20;
            const page = 64 << 10;
            const table: v8.ZigAllocatorTable = .{
                .alloc_zeroed = allocZeroed,
                .alloc = allocUninitialized,
                .free = free,
                .deinit = destroyCallback,
            };

            /// Reserves the arena (halving the request while the sandbox is short of address
            /// space) and a heap in it. Caller-owned result, released with `destroy`.
            fn create() !*SandboxState {
                const self = try mi.allocator.create(SandboxState);
                errdefer mi.allocator.destroy(self);
                var size: usize = arena_bytes;
                const base = while (size >= min_arena_bytes) : (size /= 2) {
                    if (v8.V8.sandboxReservePages(size, arena_alignment, false)) |base| break base;
                } else return error.OutOfMemory;
                errdefer v8.V8.sandboxReleasePages(base, size);
                const arena = mi.Arena.manage(base[0..size], .{}) catch return error.OutOfMemory;
                errdefer unloadArena(arena);
                const heap = try mi.Heap.createInArena(arena);
                self.* = .{ .heap = heap, .arena = arena, .base = base, .size = size };
                return self;
            }

            /// Takes an arena whose heaps are destroyed out of mimalloc. Failure would leave
            /// mimalloc visiting memory about to be unmapped, so it is fatal in every build mode.
            fn unloadArena(arena: mi.Arena.Id) void {
                arena.unload() catch @panic("mimalloc refused to unload the sandbox arena");
            }

            /// Consumes the state. Every store must already be freed; the pages go back to V8.
            fn destroy(self: *SandboxState) void {
                self.heap.destroy();
                unloadArena(self.arena);
                v8.V8.sandboxReleasePages(self.base, self.size);
                mi.allocator.destroy(self);
            }

            /// Zero-filled sandbox pages for a large store; null when the sandbox is full.
            fn allocDirect(length: usize) ?*anyopaque {
                if (length > std.math.maxInt(usize) - page) return null;
                return v8.V8.sandboxReservePages(std.mem.alignForward(usize, length, page), page, true);
            }

            /// Borrows the state; returns caller-owned sandbox storage, freed by `free` with the same
            /// length. Null on exhaustion. Zero-length requests get a minimal block.
            fn allocUninitialized(handle: ?*anyopaque, length: usize) callconv(.c) ?*anyopaque {
                const self: *SandboxState = @ptrCast(@alignCast(handle.?));
                if (length > direct_threshold) return allocDirect(length);
                return self.heap.alloc(@max(length, 1), alignment);
            }

            /// As allocUninitialized, zero-filled.
            fn allocZeroed(handle: ?*anyopaque, length: usize) callconv(.c) ?*anyopaque {
                const self: *SandboxState = @ptrCast(@alignCast(handle.?));
                if (length > direct_threshold) return allocDirect(length);
                return self.heap.allocZeroed(@max(length, 1), alignment);
            }

            /// Consumes a store from either allocate function; `length` is the one it got.
            fn free(_: ?*anyopaque, ptr: ?*anyopaque, length: usize) callconv(.c) void {
                if (length > direct_threshold) {
                    const bytes: [*]u8 = @ptrCast(ptr orelse return);
                    return v8.V8.sandboxReleasePages(bytes, std.mem.alignForward(usize, length, page));
                }
                mi.free(ptr);
            }

            fn destroyCallback(handle: ?*anyopaque) callconv(.c) void {
                const self: *SandboxState = @ptrCast(@alignCast(handle.?));
                self.destroy();
            }
        };

        /// On success the native allocator retains handle/table until deinit and
        /// invokes table.deinit(handle) once. On null neither is consumed. The caller
        /// must ensure thread-safe callbacks and valid storage for that lifetime.
        /// This low-level interface requires sandbox-compatible memory when enabled.
        pub fn newZigAllocator(handle: ?*anyopaque, vtable: *const v8.ZigAllocatorTable) ?v8.ArrayBuffer.Allocator {
            return .{ .handle = e.v8__ArrayBuffer__Allocator__NewZigAllocator(handle, vtable) orelse return null };
        }

        const ZigState = struct {
            alloc: std.mem.Allocator,
            const alignment: std.mem.Alignment = .fromByteUnits(16);
            const table: v8.ZigAllocatorTable = .{
                .alloc_zeroed = allocZeroed,
                .alloc = allocUninitialized,
                .free = free,
                .deinit = destroy,
            };

            /// Borrows stable adapter state; returns caller-owned aligned bytes, freed
            /// by free with the same length. Null retains no allocation. No V8 calls.
            fn allocUninitialized(handle: ?*anyopaque, length: usize) callconv(.c) ?*anyopaque {
                const self: *ZigState = @ptrCast(@alignCast(handle.?));
                const memory = self.alloc.alignedAlloc(u8, alignment, @max(length, 1)) catch return null;
                return memory.ptr;
            }

            /// Same ownership as allocUninitialized; initializes the requested bytes
            /// to zero before transferring ownership. Safe on V8 background threads.
            fn allocZeroed(handle: ?*anyopaque, length: usize) callconv(.c) ?*anyopaque {
                const ptr = allocUninitialized(handle, length) orelse return null;
                @memset(@as([*]u8, @ptrCast(ptr))[0..length], 0);
                return ptr;
            }

            /// Borrows state and consumes a matching backing-store allocation.
            /// Preserves allocation length/alignment, including zero-length requests.
            fn free(handle: ?*anyopaque, ptr: ?*anyopaque, length: usize) callconv(.c) void {
                const self: *ZigState = @ptrCast(@alignCast(handle.?));
                const bytes: [*]align(16) u8 = @ptrCast(@alignCast(ptr orelse return));
                self.alloc.free(bytes[0..@max(length, 1)]);
            }

            /// Consumes adapter state through its original allocator. All backing
            /// stores must have been freed; does not deinitialize the host allocator.
            fn destroy(handle: ?*anyopaque) callconv(.c) void {
                const self: *ZigState = @ptrCast(@alignCast(handle.?));
                const alloc = self.alloc;
                alloc.destroy(self);
            }
        };
    };

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn newBackingStoreWithByteLength(isolate: v8.Isolate, byte_length: usize) ?v8.BackingStore {
        return .{ .handle = e.v8__ArrayBuffer__NewBackingStore__with_byte_length(isolate.handle, byte_length) orelse return null };
    }

    /// Returns null (consuming nothing) in a V8 sandbox build: V8 aborts the process for memory
    /// outside the sandbox cage, and the default build enables the sandbox.
    pub fn newBackingStoreWithData(data_arg: ?*anyopaque, byte_length: usize, deleter: v8.Callbacks.BackingStore_DeleterCallback, deleter_data: ?*anyopaque) ?v8.BackingStore {
        if (v8.V8.isSandboxEnabled()) return null;
        return .{ .handle = e.v8__ArrayBuffer__NewBackingStore__with_data(data_arg, byte_length, deleter, deleter_data) orelse return null };
    }

    pub fn getBackingStore(self: v8.ArrayBuffer) v8.SharedBackingStore {
        const native = e.v8__ArrayBuffer__GetBackingStore(self);
        return .{ .a = native.a, .b = native.b };
    }

    pub fn data(self: v8.ArrayBuffer) ?*anyopaque {
        return e.v8__ArrayBuffer__Data(self);
    }

    pub fn detach(self: v8.ArrayBuffer, key: ?v8.Value) ?bool {
        return e.v8__ArrayBuffer__Detach(self, if (key) |v| v8.support.rawHandle(v) else null).as_optional();
    }

    pub fn isDetachable(self: v8.ArrayBuffer) bool {
        return e.v8__ArrayBuffer__IsDetachable(self);
    }

    pub fn wasDetached(self: v8.ArrayBuffer) bool {
        return e.v8__ArrayBuffer__WasDetached(self);
    }

    pub fn setDetachKey(self: v8.ArrayBuffer, key: ?v8.Value) void {
        e.v8__ArrayBuffer__SetDetachKey(self, if (key) |v| v8.support.rawHandle(v) else null);
    }

    pub fn newWithByteLength(isolate: v8.Isolate, byte_length: usize) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.from_opaque(e.v8__ArrayBuffer__New__with_byte_length(isolate.handle, byte_length));
    }

    pub fn newWithBackingStore(isolate: v8.Isolate, backing_store: *const v8.SharedBackingStore) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.from_opaque(e.v8__ArrayBuffer__New__with_backing_store(isolate.handle, backing_store));
    }

    pub fn byteLength(self: v8.ArrayBuffer) usize {
        return e.v8__ArrayBuffer__ByteLength(self);
    }
};

test "Zig ArrayBuffer adapter: failure cleanup and zero-length callback symmetry" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, ArrayBuffer.Allocator.fromZig(failing.allocator()));
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    var state: ArrayBuffer.Allocator.ZigState = .{ .alloc = std.testing.allocator };
    const empty = ArrayBuffer.Allocator.ZigState.allocZeroed(&state, 0).?;
    ArrayBuffer.Allocator.ZigState.free(&state, empty, 0);
    state.alloc = failing.allocator();
    try std.testing.expect(ArrayBuffer.Allocator.ZigState.allocUninitialized(&state, 16) == null);
    try std.testing.expect(ArrayBuffer.Allocator.ZigState.allocZeroed(&state, 16) == null);
}
