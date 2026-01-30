pub const RcData = struct {
    strong: std.atomic.Value(u32) = .init(1),

    pub fn strong_count(self: *@This()) u32 {
        return self.strong.load(.monotonic);
    }

    pub fn inc(self: *@This()) void {
        const prev = self.strong.fetchAdd(1, .monotonic);
        if (builtin.mode == .Debug) {
            if (prev > (std.math.maxInt(u32) >> 1)) {
                @panic("reference count overflow");
            }
        }
    }

    pub fn dec(self: *@This()) bool {
        const prev = self.strong.fetchSub(1, .monotonic);
        if (prev == 0) {
            return true;
        }
        return false;
    }
};

pub fn Rc(comptime T: type, comptime drop_fn: fn (*T) void) type {
    return struct {
        ptr: *T,

        pub fn init(value: T, alloc: std.mem.Allocator) !@This() {
            const alloc_size = @sizeOf(RcData) + @sizeOf(T);
            var mem = try alloc.alignedAlloc(u8, alloc_size, std.mem.Alignment.max(.of(T), .of(RcData)));
            const meta_ptr: *RcData = @ptrCast(@alignCast(mem[0..@sizeOf(RcData)]));
            const value_ptr: *T = @ptrCast(@alignCast(mem[@sizeOf(RcData)..]));
            meta_ptr.* = .{};
            value_ptr.* = value;
            return .{
                .ptr = value_ptr,
            };
        }

        pub fn raw(self: @This()) []u8 {
            const alloc_size = @sizeOf(T) + @sizeOf(RcData);
            return @as([*]u8, @ptrCast(self.meta()))[0..alloc_size];
        }

        pub fn meta(self: @This()) *RcData {
            const meta_ptr: *RcData = @ptrFromInt(@intFromPtr(self.ptr) - @sizeOf(T));
            return meta_ptr;
        }

        pub fn ref(self: @This()) void {
            self.meta().inc();
        }

        pub fn unref(self: @This(), alloc: std.mem.Allocator) void {
            if (self.meta().dec()) {
                drop_fn(&self.ptr);
                alloc.free(self.raw());
            }
        }
    };
}

pub fn RcManagedFat(comptime T: type, comptime drop_fn: fn (*T) void) type {
    return struct {
        ptr: *T,
        alloc: std.mem.Allocator,

        pub fn init(value: T, alloc: std.mem.Allocator) !@This() {
            const alloc_size = @sizeOf(RcData) + @sizeOf(T);
            var mem = try alloc.alignedAlloc(u8, alloc_size, std.mem.Alignment.max(.of(T), .of(RcData)));
            const meta_ptr: *RcData = @ptrCast(@alignCast(mem[0..@sizeOf(RcData)]));
            const value_ptr: *T = @ptrCast(@alignCast(mem[@sizeOf(RcData)..]));
            meta_ptr.* = .{};
            value_ptr.* = value;
            return .{
                .ptr = value_ptr,
            };
        }

        pub fn raw(self: @This()) []u8 {
            const alloc_size = @sizeOf(RcData) + @sizeOf(T);
            return @as([*]u8, @ptrCast(self.meta()))[0..alloc_size];
        }

        pub fn meta(self: @This()) *RcData {
            const meta_ptr: *RcData = @ptrFromInt(@intFromPtr(self.ptr) - @sizeOf(T));
            return meta_ptr;
        }

        pub fn ref(self: @This()) void {
            self.meta().inc();
        }

        pub fn unref(self: @This()) void {
            if (self.meta().dec()) {
                drop_fn(&self.ptr);
                self.alloc.free(self.raw());
            }
        }
    };
}

pub fn RcManagedThin(comptime T: type, comptime drop_fn: fn (*T) void) type {
    return struct {
        ptr: *T,

        pub fn init(value: T, alloc: std.mem.Allocator) !@This() {
            const alloc_size = @sizeOf(std.mem.Allocator) + @sizeOf(RcData) + @sizeOf(T);
            var mem = try alloc.alignedAlloc(u8, alloc_size, std.mem.Alignment.max(.of(T), .of(RcData)));
            const alloc_ptr: *std.mem.Allocator = @ptrCast(@alignCast(mem[0..@sizeOf(std.mem.Allocator)]));
            const meta_ptr: *RcData = @ptrCast(@alignCast(mem[@sizeOf(std.mem.Allocator) .. @sizeOf(std.mem.Allocator) + @sizeOf(RcData)]));
            const value_ptr: *T = @ptrCast(@alignCast(mem[@sizeOf(std.mem.Allocator) + @sizeOf(RcData) ..]));
            alloc_ptr.* = alloc;
            meta_ptr.* = .{};
            value_ptr.* = value;
            return .{
                .ptr = value_ptr,
            };
        }

        pub fn raw(self: @This()) []u8 {
            const alloc_size = @sizeOf(std.mem.Allocator) + @sizeOf(RcData) + @sizeOf(T);
            return @as([*]u8, @ptrCast(self.meta()))[0..alloc_size];
        }

        pub fn meta(self: @This()) *RcData {
            const meta_ptr: *RcData = @ptrFromInt(@intFromPtr(self.ptr) - @sizeOf(T));
            return meta_ptr;
        }

        pub fn allocator(self: @This()) std.mem.Allocator {
            const alloc_ptr: *std.mem.Allocator = @ptrFromInt(@intFromPtr(self.ptr) - @sizeOf(T) - @sizeOf(RcData));
            return alloc_ptr.*;
        }

        pub fn ref(self: @This()) void {
            self.meta().inc();
        }

        pub fn unref(self: @This()) void {
            if (self.meta().dec()) {
                drop_fn(&self.ptr);
                self.allocator().free(self.raw());
            }
        }
    };
}

const std = @import("std");
const builtin = @import("builtin");
