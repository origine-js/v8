const binding = @import("../generated/binding.zig");
const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const SnapshotCreator = extern struct {
    storage: [binding.sizes.SnapshotCreator]u8 align(@alignOf(usize)),

    pub fn init(buf: *v8.SnapshotCreator, params: *const v8.Isolate.CreateParams) void {
        e.v8__SnapshotCreator__CONSTRUCT(buf, params);
    }

    pub fn deinit(self: *v8.SnapshotCreator) void {
        e.v8__SnapshotCreator__DESTRUCT(self);
    }

    pub fn getIsolate(self: *const v8.SnapshotCreator) ?v8.Isolate {
        return .{ .handle = e.v8__SnapshotCreator__GetIsolate(self) orelse return null };
    }

    pub fn setDefaultContext(self: *v8.SnapshotCreator, context: v8.Context) void {
        e.v8__SnapshotCreator__SetDefaultContext(self, context);
    }

    pub fn addContext(self: *v8.SnapshotCreator, context: v8.Context) usize {
        return e.v8__SnapshotCreator__AddContext(self, context);
    }

    pub fn addDataToIsolate(self: *v8.SnapshotCreator, data: v8.Data) usize {
        return e.v8__SnapshotCreator__AddData_to_isolate(self, data);
    }

    pub fn addDataToContext(self: *v8.SnapshotCreator, context: v8.Context, data: v8.Data) usize {
        return e.v8__SnapshotCreator__AddData_to_context(self, context, data);
    }

    /// Mirrors `v8::SnapshotCreator::FunctionCodeHandling`.
    pub const FunctionCodeHandling = enum(c_int) { Clear, Keep };

    pub fn createBlob(self: *v8.SnapshotCreator, function_code_handling: FunctionCodeHandling) v8.StartupData {
        const blob = e.v8__SnapshotCreator__CreateBlob(self, function_code_handling);
        return .{ .data = blob.data, .raw_size = blob.raw_size };
    }
};
