const std = @import("std");
const binding = @import("../generated/binding.zig");
const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const ResourceConstraints = v8.ResourceConstraints;
const HostInitializeImportMetaObjectCallback = v8.HostInitializeImportMetaObjectCallback;
const HostImportModuleDynamicallyCallback = v8.HostImportModuleDynamicallyCallback;
const HostImportModuleWithPhaseDynamicallyCallback = v8.HostImportModuleWithPhaseDynamicallyCallback;
const Context = v8.Context;
const Data = v8.Data;
const Value = v8.Value;
const ArrayBuffer = v8.ArrayBuffer;
const HeapStatistics = v8.HeapStatistics;
const MicrotasksPolicy = v8.MicrotasksPolicy;

pub const Isolate = extern struct {
    pub const Opaque = opaque {};

    pub const CreateParams = extern struct {
        code_event_handler: ?*const anyopaque = null,
        constraints: ResourceConstraints = std.mem.zeroes(ResourceConstraints),
        snapshot_blob: ?*const anyopaque = null,
        counter_lookup_callback: ?*const anyopaque = null,
        create_histogram_callback: ?*const anyopaque = null,
        add_histogram_sample_callback: ?*const anyopaque = null,
        array_buffer_allocator: ArrayBuffer.Allocator,
        array_buffer_allocator_shared: [2]?*anyopaque = .{ null, null },
        external_references: ?*const isize = null,
        /// Copied into the isolate; controls blocking Atomics.wait only.
        /// Atomics, Atomics.waitAsync and SharedArrayBuffer remain available.
        allow_explicit_blocking_api: bool = false,
        _fatal_error_handler: ?*const anyopaque = null,
        _oom_error_handler: ?*const anyopaque = null,
        cpp_heap: ?*const anyopaque = null,

        /// Returns value-owned parameters; retains no resources. Initializes V8's
        /// defaults with blocking Atomics.wait disabled for Zig-created isolates.
        pub fn init() CreateParams {
            comptime {
                if (@sizeOf(CreateParams) != binding.sizes.Isolate_CreateParams) {
                    @compileError("Isolate.CreateParams size mismatch");
                }
            }
            var params: CreateParams = undefined;
            e.v8__Isolate__CreateParams__CONSTRUCT(&params);
            params.allow_explicit_blocking_api = false;
            return params;
        }
    };

    handle: *Opaque,

    const Self = @This();

    pub fn init(params: *const CreateParams) Self {
        return .{
            .handle = e.v8__Isolate__New(params).?,
        };
    }

    pub fn deinit(self: Self) void {
        e.v8__Isolate__Dispose(self.handle);
    }

    pub fn enter(self: Self) void {
        e.v8__Isolate__Enter(self.handle);
    }

    pub fn exit(self: Self) void {
        e.v8__Isolate__Exit(self.handle);
    }

    pub fn getCurrent() Self {
        return .{
            .handle = e.v8__Isolate__GetCurrent().?,
        };
    }

    pub fn getCurrentContext(self: Self) Context {
        return .{
            .data = Data.from_opaque(e.v8__Isolate__GetCurrentContext(self.handle)).?,
        };
    }

    pub fn throwException(self: Self, value: Value) ?Value {
        return .from_opaque(e.v8__Isolate__ThrowException(self.handle, value));
    }

    pub fn setData(self: Self, slot: u32, data: ?*anyopaque) void {
        e.v8__Isolate__SetData(self.handle, slot, data);
    }

    pub fn getData(self: Self, slot: u32) ?*anyopaque {
        return e.v8__Isolate__GetData(self.handle, slot);
    }

    pub fn performMicrotasksCheckpoint(self: Self) void {
        e.v8__Isolate__PerformMicrotaskCheckpoint(self.handle);
    }

    pub fn getMicrotasksPolicy(self: Self) MicrotasksPolicy {
        return e.v8__Isolate__GetMicrotasksPolicy(self.handle);
    }

    pub fn setMicrotasksPolicy(self: Self, policy: MicrotasksPolicy) void {
        e.v8__Isolate__SetMicrotasksPolicy(self.handle, policy);
    }

    pub fn lowMemoryNotification(self: Self) void {
        e.v8__Isolate__LowMemoryNotification(self.handle);
    }

    pub fn terminateExecution(self: Self) void {
        e.v8__Isolate__TerminateExecution(self.handle);
    }

    pub fn isExecutionTerminating(self: Self) bool {
        return e.v8__Isolate__IsExecutionTerminating(self.handle);
    }

    pub fn cancelTerminateExecution(self: Self) void {
        e.v8__Isolate__CancelTerminateExecution(self.handle);
    }

    pub fn getHeapStatistics(self: Self) HeapStatistics {
        var res: HeapStatistics = undefined;
        e.v8__Isolate__GetHeapStatistics(self.handle, &res);
        return res;
    }

    pub fn setCaptureStackTraceForUncaughtExceptions(self: Self, capture: bool, frame_limit: c_int) void {
        e.v8__Isolate__SetCaptureStackTraceForUncaughtExceptions(self.handle, capture, frame_limit);
    }

    pub fn setHostInitializeImportMetaObjectCallback(self: Self, callback: HostInitializeImportMetaObjectCallback) void {
        e.v8__Isolate__SetHostInitializeImportMetaObjectCallback(self.handle, callback);
    }

    pub fn setHostImportModuleDynamicallyCallback(self: Self, callback: HostImportModuleDynamicallyCallback) void {
        e.v8__Isolate__SetHostImportModuleDynamicallyCallback(self.handle, callback);
    }

    pub fn setHostImportModuleWithPhaseDynamicallyCallback(self: Self, callback: HostImportModuleWithPhaseDynamicallyCallback) void {
        e.v8__Isolate__SetHostImportModuleWithPhaseDynamicallyCallback(self.handle, callback);
    }

    pub fn getCurrentHostDefinedOptions(isolate: v8.Isolate) ?v8.Data {
        return v8.Data.from_opaque(e.v8__Isolate__GetCurrentHostDefinedOptions(isolate.handle));
    }

    pub fn memoryPressureNotification(isolate: v8.Isolate, level: v8.MemoryPressureLevel) void {
        e.v8__Isolate__MemoryPressureNotification(isolate.handle, level);
    }

    pub fn clearKeptObjects(isolate: v8.Isolate) void {
        e.v8__Isolate__ClearKeptObjects(isolate.handle);
    }

    pub fn getEnteredOrMicrotaskContext(isolate: v8.Isolate) ?v8.Context {
        return v8.Context.from_opaque(e.v8__Isolate__GetEnteredOrMicrotaskContext(isolate.handle));
    }

    pub fn getNumberOfDataSlots(isolate: v8.Isolate) u32 {
        return e.v8__Isolate__GetNumberOfDataSlots(isolate.handle);
    }

    pub fn getDataFromSnapshotOnce(isolate: v8.Isolate, index: usize) ?v8.Data {
        return v8.Data.from_opaque(e.v8__Isolate__GetDataFromSnapshotOnce(isolate.handle, index));
    }

    pub fn enqueueMicrotask(isolate: v8.Isolate, function: v8.Function) void {
        e.v8__Isolate__EnqueueMicrotask(isolate.handle, function);
    }

    pub fn requestInterrupt(isolate: v8.Isolate, callback: v8.Callbacks.InterruptCallback, data: ?*anyopaque) void {
        e.v8__Isolate__RequestInterrupt(isolate.handle, callback, data);
    }

    pub fn setPrepareStackTraceCallback(isolate: v8.Isolate, callback: v8.Callbacks.PrepareStackTraceCallback) void {
        e.v8__Isolate__SetPrepareStackTraceCallback(isolate.handle, callback);
    }

    pub fn setPromiseHook(isolate: v8.Isolate, hook: v8.Callbacks.PromiseHook) void {
        e.v8__Isolate__SetPromiseHook(isolate.handle, hook);
    }

    pub fn setPromiseRejectCallback(isolate: v8.Isolate, callback: v8.Callbacks.PromiseRejectCallback) void {
        e.v8__Isolate__SetPromiseRejectCallback(isolate.handle, callback);
    }

    pub fn setHostCreateShadowRealmContextCallback(isolate: v8.Isolate, callback: v8.Callbacks.HostCreateShadowRealmContextCallback) void {
        e.v8__Isolate__SetHostCreateShadowRealmContextCallback(isolate.handle, callback);
    }

    pub fn setUseCounterCallback(isolate: v8.Isolate, callback: v8.Callbacks.Isolate_UseCounterCallback) void {
        e.v8__Isolate__SetUseCounterCallback(isolate.handle, callback);
    }

    pub fn addMessageListener(isolate: v8.Isolate, callback: v8.Callbacks.MessageCallback) bool {
        return e.v8__Isolate__AddMessageListener(isolate.handle, callback);
    }

    /// Mirrors `v8::Isolate::MessageErrorLevel` (bit flags selecting which message levels reach a listener).
    pub const MessageErrorLevel = packed struct(c_int) {
        Log: bool = false,
        Debug: bool = false,
        Info: bool = false,
        Error: bool = false,
        Warning: bool = false,
        _unused: u27 = 0,

        /// `kMessageAll`.
        pub const all: MessageErrorLevel = .{ .Log = true, .Debug = true, .Info = true, .Error = true, .Warning = true };
    };

    /// Mirrors `v8::Isolate::TimeZoneDetection`.
    pub const TimeZoneDetection = enum(c_int) { Skip, Redetect };

    pub fn addMessageListenerWithErrorLevel(isolate: v8.Isolate, callback: v8.Callbacks.MessageCallback, error_level: MessageErrorLevel) bool {
        return e.v8__Isolate__AddMessageListenerWithErrorLevel(isolate.handle, callback, @bitCast(error_level));
    }

    pub fn addGCPrologueCallback(isolate: v8.Isolate, callback: v8.Callbacks.Isolate_GCCallbackWithData, data: ?*anyopaque, gc_type_filter: u32) void {
        e.v8__Isolate__AddGCPrologueCallback(isolate.handle, callback, data, gc_type_filter);
    }

    pub fn removeGCPrologueCallback(isolate: v8.Isolate, callback: v8.Callbacks.Isolate_GCCallbackWithData, data: ?*anyopaque) void {
        e.v8__Isolate__RemoveGCPrologueCallback(isolate.handle, callback, data);
    }

    pub fn addGCEpilogueCallback(isolate: v8.Isolate, callback: v8.Callbacks.Isolate_GCCallbackWithData, data: ?*anyopaque, gc_type_filter: u32) void {
        e.v8__Isolate__AddGCEpilogueCallback(isolate.handle, callback, data, gc_type_filter);
    }

    pub fn removeGCEpilogueCallback(isolate: v8.Isolate, callback: v8.Callbacks.Isolate_GCCallbackWithData, data: ?*anyopaque) void {
        e.v8__Isolate__RemoveGCEpilogueCallback(isolate.handle, callback, data);
    }

    pub fn addNearHeapLimitCallback(isolate: v8.Isolate, callback: v8.Callbacks.NearHeapLimitCallback, data: ?*anyopaque) void {
        e.v8__Isolate__AddNearHeapLimitCallback(isolate.handle, callback, data);
    }

    pub fn numberOfHeapSpaces(isolate: v8.Isolate) usize {
        return e.v8__Isolate__NumberOfHeapSpaces(isolate.handle);
    }

    pub fn getHeapSpaceStatistics(isolate: v8.Isolate, space_statistics: *v8.HeapSpaceStatistics, index: usize) bool {
        return e.v8__Isolate__GetHeapSpaceStatistics(isolate.handle, space_statistics, index);
    }

    pub fn removeNearHeapLimitCallback(isolate: v8.Isolate, callback: v8.Callbacks.NearHeapLimitCallback, heap_limit: usize) void {
        e.v8__Isolate__RemoveNearHeapLimitCallback(isolate.handle, callback, heap_limit);
    }

    pub fn adjustAmountOfExternalAllocatedMemory(isolate: v8.Isolate, change_in_bytes: i64) i64 {
        return e.v8__Isolate__AdjustAmountOfExternalAllocatedMemory(isolate.handle, change_in_bytes);
    }

    pub fn setOOMErrorHandler(isolate: v8.Isolate, callback: v8.Callbacks.OOMErrorCallback) void {
        e.v8__Isolate__SetOOMErrorHandler(isolate.handle, callback);
    }

    /// Copies allow into this isolate on its owning thread; retains no resources.
    /// Changes blocking Atomics.wait permission in existing and future contexts.
    /// Does not hide Atomics or affect Atomics.waitAsync.
    pub fn setAllowExplicitBlockingApi(isolate: v8.Isolate, allow: bool) void {
        e.v8__Isolate__SetAllowAtomicsWait(isolate.handle, allow);
    }

    pub fn hasPendingBackgroundTasks(isolate: v8.Isolate) bool {
        return e.v8__Isolate__HasPendingBackgroundTasks(isolate.handle);
    }

    pub fn requestGarbageCollectionForTesting(isolate: v8.Isolate, @"type": u32) void {
        e.v8__Isolate__RequestGarbageCollectionForTesting(isolate.handle, @"type");
    }

    pub fn dateTimeConfigurationChangeNotification(isolate: v8.Isolate, time_zone_detection: TimeZoneDetection) void {
        e.v8__Isolate__DateTimeConfigurationChangeNotification(isolate.handle, time_zone_detection);
    }
    /// Construct in place; do not copy an active execution scope.
    pub const AllowJavascriptExecutionScope = extern struct {
        storage: [binding.sizes.Isolate_AllowJavascriptExecutionScope]u8 align(@alignOf(usize)),

        pub fn init(self: *@This(), isolate: v8.Isolate) void {
            e.v8__AllowJavascriptExecutionScope__CONSTRUCT(self, isolate.handle);
        }
        pub fn deinit(self: *@This()) void {
            e.v8__AllowJavascriptExecutionScope__DESTRUCT(self);
        }
    };
    /// Construct in place; do not copy an active execution scope.
    pub const DisallowJavascriptExecutionScope = extern struct {
        storage: [binding.sizes.Isolate_DisallowJavascriptExecutionScope]u8 align(@alignOf(usize)),
        pub const OnFailure = enum(c_uint) { crash, throw, dump };
        pub fn init(self: *@This(), isolate: v8.Isolate, on_failure: OnFailure) void {
            e.v8__DisallowJavascriptExecutionScope__CONSTRUCT(self, isolate.handle, on_failure);
        }
        pub fn deinit(self: *@This()) void {
            e.v8__DisallowJavascriptExecutionScope__DESTRUCT(self);
        }
    };
};
