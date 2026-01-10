const std = @import("std");
pub const gpa: std.mem.Allocator = std.heap.smp_allocator;

const alloc_align = 16;
const enable_tagging = false;

var min_ptr: usize = 0xFFFF_FFFF_FFFF_FFFF;
var max_ptr: usize = 0;

// var original_free: ?*const fn (?*anyopaque) callconv(.c) void = null;

// fn get_original_free() *const fn (?*anyopaque) callconv(.c) void {
//     if (original_free) |f| return f;
//     // RTLD_NEXT finds the next occurrence of 'free' in the library search order
//     const handle = std.posix.system.dlopen(null, std.posix.system.RTLD{ .LAZY = true, .GLOBAL = true });
//     const f = std.posix.system.dlsym(handle, "free");
//     original_free = @ptrCast(@alignCast(f));
//     return original_free.?;
// }

const MallocMeta = struct {
    pub const Tags = if (enable_tagging) enum(u16) {
        init = 0xbeef,
        resi = 0xaeae,
        free = 0xafaf,
    } else struct {
        pub const init = {};
        pub const free = {};
        pub const resi = {};
    };

    tag: if (enable_tagging) Tags else void,
    alloc_size: usize,

    const Alignment = std.mem.Alignment.max(
        .fromByteUnits(@alignOf(MallocMeta)),
        .fromByteUnits(alloc_align),
    );

    const aligned_size = std.mem.alignForward(usize, @sizeOf(MallocMeta), 16);

    pub inline fn allocate(alloc: std.mem.Allocator, size: usize) ?struct { *@This(), []u8 } {
        const alloc_size = aligned_size + size;
        const mem = alloc.alignedAlloc(u8, Alignment, alloc_size) catch return null;
        errdefer alloc.free(mem);
        const meta: *MallocMeta = @ptrCast(mem.ptr[0..@sizeOf(MallocMeta)]);
        meta.* = .{
            .tag = Tags.init,
            .alloc_size = alloc_size,
        };
        _ = @atomicRmw(usize, &min_ptr, .Min, @intFromPtr(mem.ptr) + aligned_size, .monotonic);
        _ = @atomicRmw(usize, &max_ptr, .Max, @intFromPtr(mem.ptr) + aligned_size, .monotonic);
        return .{ meta, mem.ptr[aligned_size..mem.len] };
    }

    pub inline fn as_mem(self: *@This()) []u8 {
        const mem: [*]u8 = @ptrCast(self);
        return mem[0..self.alloc_size];
    }

    pub inline fn get_data(self: *@This()) []u8 {
        const mem: [*]u8 = @ptrCast(self);
        return mem[aligned_size..self.alloc_size];
    }

    pub inline fn reallocate(self: **@This(), alloc: std.mem.Allocator, new_size: usize) !void {
        self.*.tag = Tags.resi;
        const new_alloc_size = aligned_size + new_size;
        const new_mem = try alloc.realloc(self.*.as_mem(), new_alloc_size);
        const new_meta: *@This() = @ptrCast(@alignCast(new_mem));
        new_meta.* = .{
            .tag = Tags.init,
            .alloc_size = new_alloc_size,
        };
        self.* = new_meta;
    }

    pub inline fn deallocate(self: *@This(), alloc: std.mem.Allocator) void {
        self.tag = Tags.free; // freed
        const mem: [*]u8 = @ptrCast(self);
        alloc.free(mem[0..self.alloc_size]);
    }

    pub inline fn from(ptr: *anyopaque) !*@This() {
        const l_max_ptr = @atomicLoad(usize, &max_ptr, .monotonic);
        const l_min_ptr = @atomicLoad(usize, &min_ptr, .monotonic);
        if (@intFromPtr(ptr) < l_min_ptr or @intFromPtr(ptr) > l_max_ptr) {
            return error.BadPtr;
        }
        var mem: [*]u8 = @ptrCast(ptr);
        mem -= aligned_size;
        const meta: *MallocMeta = @ptrCast(@alignCast(mem[0..@sizeOf(MallocMeta)]));
        if (enable_tagging and meta.tag == Tags.free) {
            return error.BadMem;
        }
        if (meta.tag != Tags.init) {
            return error.BadTag;
        }
        return meta;
    }
};

pub export fn malloc(size: usize) callconv(.c) ?*anyopaque {
    const meta, const mem = MallocMeta.allocate(gpa, size) orelse return null;
    _ = meta;
    // std.debug.print("@ -> malloc({}) = {*}\n", .{ size, mem.ptr });
    return @ptrCast(mem);
}

pub export fn free(maybe_ptr: ?*anyopaque) callconv(.c) void {
    const ptr = maybe_ptr orelse return;
    // std.debug.print("@ -> free({ptr})\n", .{ptr});
    const meta = MallocMeta.from(ptr) catch {
        // get_original_free()(ptr);
        return;
    };
    meta.deallocate(gpa);
}

pub export fn calloc(num: usize, size: usize) callconv(.c) ?*anyopaque {
    const res, const of = @mulWithOverflow(num, size);
    if (of == 1) return null;
    const meta, const mem = MallocMeta.allocate(gpa, res) orelse return null;
    // std.debug.print("@ -> calloc({}, {}) = {*}\n", .{ num, size, mem });
    _ = meta;
    @memset(mem, 0);
    return @ptrCast(mem);
}

pub export fn realloc(maybe_ptr: ?*anyopaque, size: usize) ?*anyopaque {
    const ptr = maybe_ptr orelse {
        return malloc(size);
    };
    var meta = MallocMeta.from(ptr) catch return null;
    if (size == 0) {
        meta.deallocate(gpa);
        return null;
    }
    MallocMeta.reallocate(&meta, gpa, size) catch return null;
    const mem = meta.get_data();
    // std.debug.print("@ -> realloc({ptr}, {}) = {*}\n", .{ ptr, size, mem });
    return @ptrCast(mem);
}

// This tells V8 how much space is actually in the block.
// Without this, V8 assumes 0 and crashes.
pub export fn malloc_usable_size(ptr: ?*anyopaque) callconv(.c) usize {
    const p = ptr orelse return 0;
    const meta = MallocMeta.from(p) catch return 0;
    return meta.get_data().len;
}

// For macOS compatibility
pub export fn malloc_size(ptr: ?*anyopaque) callconv(.c) usize {
    return malloc_usable_size(ptr);
}

pub export fn _msize(ptr: ?*anyopaque) callconv(.c) usize {
    return malloc_usable_size(ptr);
}
