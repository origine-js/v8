const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const ObjectTemplate = v8.ObjectTemplate;
const MicrotaskQueue = v8.MicrotaskQueue;
const MaybeHandle = v8.MaybeHandle;
const Data = v8.Data;
const Value = v8.Value;
const Object = v8.Object;
const Function = v8.Function;

pub const Context = extern struct {
    data: Data,

    const Self = @This();

    /// Borrows this context on its isolate thread with the isolate entered and
    /// a live HandleScope. Returns a native setting by value; retains nothing.
    pub fn getStackTraceLimit(self: Self) v8.StackTraceLimit {
        return .fromNative(e.v8__Context__GetStackTraceLimit(self));
    }

    /// Copies limit into this context for subsequent captures. Requires its
    /// isolate entered on its owning thread and a live HandleScope; retains no
    /// caller resources and does not access JavaScript properties or run getters.
    pub fn setStackTraceLimit(self: Self, limit: v8.StackTraceLimit) void {
        e.v8__Context__SetStackTraceLimit(self, limit.toNative());
    }

    pub fn from_opaque(o: MaybeHandle) ?Self {
        return .{ .data = Data.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, global_tmpl: ?ObjectTemplate, global_obj: ?Value, microtask_queue: ?MicrotaskQueue) Self {
        return .{
            .data = Data.from_opaque(e.v8__Context__New(
                isolate.handle,
                (global_tmpl orelse ObjectTemplate.initDefault(isolate).?).template.data.handle,
                if (global_obj) |v| v.data.handle else null,
                if (microtask_queue) |v| v.handle else null,
            )).?,
        };
    }

    pub fn enter(self: Self) void {
        e.v8__Context__Enter(self);
    }

    pub fn exit(self: Self) void {
        e.v8__Context__Exit(self);
    }

    pub fn getGlobal(self: Self) Object {
        return .{
            .value = Value.from_opaque(e.v8__Context__Global(self)).?,
        };
    }

    pub fn getEmbedderData(self: Self, index: c_int) Data {
        return Data.from_opaque(e.v8__Context__GetEmbedderData(self, index)).?;
    }

    pub fn setEmbedderData(self: Self, index: u32, value: Data) void {
        e.v8__Context__SetEmbedderData(self, @as(c_int, @intCast(index)), value.handle);
    }

    pub fn eq(self: Self, other: Self) bool {
        return e.v8__Context__EQ(self, other);
    }

    pub fn getNumberOfEmbedderDataFields(self: Self) u32 {
        return e.v8__Context__GetNumberOfEmbedderDataFields(self);
    }

    pub fn getAlignedPointerFromEmbedderData(self: Self, index: u32) ?*anyopaque {
        return e.v8__Context__GetAlignedPointerFromEmbedderData(self, @intCast(index));
    }

    /// The pointer must be aligned to 2 bytes.
    pub fn setAlignedPointerInEmbedderData(self: Self, index: u32, value: ?*anyopaque) void {
        e.v8__Context__SetAlignedPointerInEmbedderData(self, @intCast(index), value);
    }

    pub fn getDataFromSnapshotOnce(self: Self, index: usize) ?Data {
        return .from_opaque(e.v8__Context__GetDataFromSnapshotOnce(self, index));
    }

    pub fn getExtrasBindingObject(self: Self) ?Object {
        return .from_opaque(e.v8__Context__GetExtrasBindingObject(self));
    }

    pub fn setPromiseHooks(self: Self, init_hook: ?Function, before_hook: ?Function, after_hook: ?Function, resolve_hook: ?Function) void {
        e.v8__Context__SetPromiseHooks(self, fnHandle(init_hook), fnHandle(before_hook), fnHandle(after_hook), fnHandle(resolve_hook));
    }

    fn fnHandle(f: ?Function) MaybeHandle {
        return if (f) |x| x.object.value.data.handle else null;
    }

    pub fn getSecurityToken(self: Self) ?Value {
        return .from_opaque(e.v8__Context__GetSecurityToken(self));
    }

    pub fn setSecurityToken(self: Self, token: Value) void {
        e.v8__Context__SetSecurityToken(self, token.data.handle);
    }

    pub fn useDefaultSecurityToken(self: Self) void {
        e.v8__Context__UseDefaultSecurityToken(self);
    }

    pub fn allowCodeGenerationFromStrings(self: Self, allow: bool) void {
        e.v8__Context__AllowCodeGenerationFromStrings(self, allow);
    }

    pub fn isCodeGenerationFromStringsAllowed(self: Self) bool {
        return e.v8__Context_IsCodeGenerationFromStringsAllowed(self);
    }

    pub fn getMicrotaskQueue(self: Self) ?MicrotaskQueue {
        return .{ .handle = e.v8__Context__GetMicrotaskQueue(self) orelse return null };
    }

    pub fn setMicrotaskQueue(self: Self, queue: MicrotaskQueue) void {
        e.v8__Context__SetMicrotaskQueue(self, queue.handle);
    }

    pub fn fromSnapshot(isolate: Isolate, index: usize, global_object: ?Value, microtask_queue: ?MicrotaskQueue) ?Self {
        return .from_opaque(e.v8__Context__FromSnapshot(
            isolate.handle,
            index,
            if (global_object) |v| v.data.handle else null,
            if (microtask_queue) |q| q.handle else null,
        ));
    }

    pub fn setContinuationPreservedEmbedderData(isolate: Isolate, data: ?Value) void {
        e.v8__Context__SetContinuationPreservedEmbedderData(isolate.handle, if (data) |v| v.data.handle else null);
    }

    pub fn getContinuationPreservedEmbedderData(isolate: Isolate) ?Value {
        return .from_opaque(e.v8__Context__GetContinuationPreservedEmbedderData(isolate.handle));
    }
};
