const std = @import("std");
const binding = @import("./binding.zig");
const e = @import("./externs.gen.zig");

pub const support = struct {
    pub fn Maybe(comptime T: type) type {
        return extern struct {
            has_value: bool,
            value: T,

            pub fn as_optional(self: @This()) ?T {
                if (!self.has_value) return null;
                return self.value;
            }
            pub fn from_optional(opt: ?T) @This() {
                return .{
                    .has_value = if (opt) |_| true else false,
                    .value = if (opt) |v| v else undefined,
                };
            }
        };
    }

    pub const MaybeBool = enum(c_int) {
        JustFalse = 0,
        JustTrue = 1,
        Nothing = 2,

        pub fn from_optional(opt: ?bool) @This() {
            return switch (opt orelse return .Nothing) {
                true => .JustTrue,
                false => .JustFalse,
            };
        }

        pub fn as_optional(self: @This()) ?bool {
            return switch (self) {
                @This().JustFalse => false,
                @This().JustTrue => true,
                @This().Nothing => null,
            };
        }
    };
};

pub const Platform = struct {
    pub const Opaque = opaque {};


    handle: *Opaque,

    const Self = @This();

    /// Returns a new instance of the default v8::Platform implementation.
    /// |thread_pool_size| is the number of worker threads to allocate for background jobs.
    /// If 0, a suitable default based on the processors will be chosen.
    pub fn initDefault(thread_pool_size: u32, idle_task_support: bool) Self {
        return .{
            .handle = e.v8__Platform__NewDefaultPlatform(@as(c_int, @intCast(thread_pool_size)), idle_task_support).?,
        };
    }

    pub fn deinit(self: Self) void {
        e.v8__Platform__DELETE(self.handle);
    }

    /// Pumps the message loop for the given isolate.
    pub fn pumpMessageLoop(self: Self, isolate: Isolate, wait_for_work: bool) bool {
        return e.v8__Platform__PumpMessageLoop(self.handle, isolate.handle, wait_for_work);
    }
};

pub const V8 = struct {

    /// Initializes V8. This function needs to be called before the first Isolate is created.
    pub fn initialize() void {
        e.v8__V8__Initialize();
    }

    /// Sets the v8::Platform to use. This should be invoked before V8 is initialized.
    pub fn initializePlatform(platform: Platform) void {
        e.v8__V8__InitializePlatform(platform.handle);
    }

    /// Initializes the ICU bundled with v8.
    pub fn initializeICU() bool {
        return e.v8__V8__InitializeICU();
    }

    /// Releases any resources used by v8 and stops any utility thread that may be running.
    pub fn dispose() void {
        _ = e.v8__V8__Dispose();
    }

    /// Clears all references to the v8::Platform. This should be invoked after V8 was disposed.
    pub fn disposePlatform() void {
        e.v8__V8__DisposePlatform();
    }
};

pub const ResourceConstraints = extern struct {
    code_range_size_: usize,
    max_old_generation_size_: usize,
    max_young_generation_size_: usize,
    initial_old_generation_size_: usize,
    initial_young_generation_size_: usize,
    physical_memory_size_: u64,
    stack_limit_: *const u32,
};

pub const FixedArray = extern struct {

    data: Data,

    pub fn len(self: @This()) c_int {
        return e.v8__FixedArray__Length(self);
    }

    pub fn get(self: @This(), idx: c_int) ?Data {
        return .from_opaque(e.v8__FixedArray__Get(self, idx));
    }
};

pub const PrimitiveArray = extern struct {

    data: Data,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .data = Data.from_opaque(o) orelse return null,
        };
    }

    pub fn init(isolate: Isolate, length: c_int) @This() {
        return @This().from_opaque(e.v8__PrimitiveArray__New(isolate.handle, length)).?;
    }

    pub fn set(self: @This(), isolate: Isolate, index: c_int, primitive: Primitive) void {
        e.v8__PrimitiveArray__Set(self, isolate.handle, index, primitive);
    }

    pub fn get(self: @This(), isolate: Isolate, index: c_int) Primitive {
        return Primitive.from_opaque(e.v8__PrimitiveArray__Get(self, isolate.handle, index)).?;
    }
};

pub const Array = extern struct {

    object: Object,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .object = Object.from_opaque(o) orelse return null,
        };
    }

    pub fn init(isolate: Isolate, length: c_int) @This() {
        return @This().from_opaque(e.v8__Array__New(isolate.handle, length)).?;
    }

    pub fn with_elements(isolate: Isolate, elements: []const Value) ?@This() {
        return @This().from_opaque(e.v8__Array__New_with_elements(isolate.handle, @ptrCast(elements.ptr), elements.len));
    }

    pub fn len(self: @This()) u32 {
        return e.v8__Array__Length(self);
    }
};

pub const ModuleImportPhase = enum(c_int) {
    Source,
    Defer,
    Evaluation,
};

pub const HostInitializeImportMetaObjectCallback = *const fn (Context, Module, meta: Object) callconv(.c) void;
pub const HostImportModuleDynamicallyCallback = *const fn (Context, host_defined_options: Data, resource_name: Value, specifier: String, import_attributes: FixedArray) callconv(.c) Promise;
pub const HostImportModuleWithPhaseDynamicallyCallback = *const fn (Context, host_defined_options: Data, resource_name: Value, specifier: String, ModuleImportPhase, import_attributes: FixedArray) callconv(.c) Promise;

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
        allow_atomics_wait: bool = true,
        _fatal_error_handler: ?*const anyopaque = null,
        _oom_error_handler: ?*const anyopaque = null,
        cpp_heap: ?*const anyopaque = null,

        pub fn init() CreateParams {
            comptime {
                if (@sizeOf(CreateParams) != binding.sizes.Isolate_CreateParams) {
                    @compileError("Isolate.CreateParams size mismatch");
                }
            }
            var params: CreateParams = undefined;
            e.v8__Isolate__CreateParams__CONSTRUCT(&params);
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
};

pub const HandleScope = struct {
    pub const Opaque = [binding.sizes.HandleScope]u8;


    inner: Opaque,

    const Self = @This();

    pub fn init(self: *Self, isolate: Isolate) void {
        e.v8__HandleScope__CONSTRUCT(&self.inner, isolate.handle);
    }

    pub fn deinit(self: *Self) void {
        e.v8__HandleScope__DESTRUCT(&self.inner);
    }
};

pub const CTypeInfo = extern struct {
    type: enum(u8) {
        Void = 1,
        Bool = 2,
        Uint8 = 3,
        Int32 = 4,
        Uint32 = 5,
        Int64 = 6,
        Uint64 = 7,
        Float32 = 8,
        Float64 = 9,
        Pointer = 10,
        V8Value = 11,
    },
    /// `v8::CTypeInfo::Flags` is a `uint8_t` enum: sizeof(CTypeInfo) == 2.
    flags: packed struct(u8) {
        AllowSharedBit: bool,
        EnforceRangeBit: bool,
        ClampBit: bool,
        IsRestrictedBit: bool,
        _unused: u4 = 0,
    },
};

pub const CFunctionInfo = extern struct {
    pub const Int64Representation = enum(u8) {
        Number,
        BigInt,
    };

    return_info_: CTypeInfo,
    repr_: Int64Representation,
    arg_count_: c_uint,
    arg_info_: *const CTypeInfo,
};

pub const CFunction = extern struct {
    pub const OverloadResolution = enum(c_int) {
        Impossible,
        AtRuntime,
        AtCompileTime,
    };

    address_: *anyopaque,
    type_info_: *const CFunctionInfo,
};

pub const ReturnValue = extern struct {

    addr: usize,

    pub fn set(self: *@This(), value: Value) void {
        e.v8__ReturnValue__Value__Set(self, value);
    }

    pub fn setBool(self: *@This(), i: bool) void {
        e.v8__ReturnValue__Value__Set__Bool(self, i);
    }

    pub fn setInt32(self: *@This(), i: i32) void {
        e.v8__ReturnValue__Value__Set__Int32(self, i);
    }

    pub fn setUint32(self: *@This(), i: u32) void {
        e.v8__ReturnValue__Value__Set__Uint32(self, i);
    }

    pub fn setDouble(self: *@This(), i: f64) void {
        e.v8__ReturnValue__Value__Set__Double(self, i);
    }

    pub fn setNull(self: *@This()) void {
        e.v8__ReturnValue__Value__SetNull(self);
    }

    pub fn setUndefined(self: *@This()) void {
        e.v8__ReturnValue__Value__SetUndefined(self);
    }

    pub fn setEmptyString(self: *@This()) void {
        e.v8__ReturnValue__Value__SetEmptyString(self);
    }

    pub fn get(self: *const @This()) ?Value {
        return Value.from_opaque(e.v8__ReturnValue__Value__Get(self));
    }
};

pub const PropertyCallbackInfo = extern struct {
    pub const Opaque = [binding.sizes.PropertyCallbackInfo]u8;


    inner: Opaque,

    pub fn isolate(self: *const @This()) Isolate {
        return .{ .handle = e.v8__PropertyCallbackInfo__GetIsolate(self).? };
    }

    pub fn data(self: *const @This()) ?Data {
        return Data.from_opaque(e.v8__PropertyCallbackInfo__Data(self));
    }

    pub fn this(self: *const @This()) Object {
        return Object.from_opaque(e.v8__PropertyCallbackInfo__This(self)).?;
    }

    pub fn holder(self: *const @This()) Object {
        return Object.from_opaque(e.v8__PropertyCallbackInfo__Holder(self)).?;
    }

    pub fn retval(self: *const @This()) ReturnValue {
        return .{ .addr = @intFromPtr(e.v8__PropertyCallbackInfo__GetReturnValue(self)) };
    }

    pub fn shouldThrowOnError(self: *const @This()) bool {
        return e.v8__PropertyCallbackInfo__ShouldThrowOnError(self);
    }

    comptime {
        std.debug.assert(@sizeOf(PropertyCallbackInfo) == binding.sizes.PropertyCallbackInfo);
    }
};

pub const AccessorNameGetterCallback = *const fn (Name, *const PropertyCallbackInfo) callconv(.c) void;
pub const AccessorNameSetterCallback = *const fn (Name, Value, *const PropertyCallbackInfo) callconv(.c) void;

// https://github.com/denoland/rusty_v8/blob/4d9f92762600fd3475a5632005ecf3721514b8d4/src/property_attribute.rs#L5
pub const PropertyDescriptor = extern struct {
    pub const Opaque = [binding.sizes.PropertyDescriptor]u8;
    inner: Opaque,


    pub fn init() PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        e.v8__PropertyDescriptor__CONSTRUCT(&self.inner);
        return self;
    }

    pub fn initValue(value: Value, writable: ?bool) PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        if (writable) |w| {
            e.v8__PropertyDescriptor__CONSTRUCT__Value_Writable(&self.inner, value, w);
        } else {
            e.v8__PropertyDescriptor__CONSTRUCT__Value(&self.inner, value);
        }
        return self;
    }

    pub fn initGetSet(get: Value, set: Value) PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        e.v8__PropertyDescriptor__CONSTRUCT__Get_Set(&self.inner, get, set);
        return self;
    }

    pub fn deinit(self: *PropertyDescriptor) void {
        e.v8__PropertyDescriptor__DESTRUCT(&self.inner);
    }
};

pub const PropertyAttribute = packed struct(u32) {
    ReadOnly: bool = false,
    DontEnum: bool = false,
    DontDelete: bool = false,
    _unused: u29 = 0,
};

pub const Template = extern struct {

    data: Data,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .data = Data.from_opaque(o) orelse return null };
    }

    pub fn set(self: @This(), key: Name, value: Data, attr: PropertyAttribute) void {
        e.v8__Template__Set(self, key, value, attr);
    }
};

pub const FunctionCallbackInfo = extern struct {
    pub const Opaque = opaque {};


    inner: *Opaque,

    pub fn data(self: @This()) ?Data {
        return Data.from_opaque(e.v8__FunctionCallbackInfo__Data(self));
    }

    pub fn length(self: @This()) c_int {
        return e.v8__FunctionCallbackInfo__Length(self);
    }

    pub fn get_arg(self: @This(), index: c_int) Value {
        return Value.from_opaque(e.v8__FunctionCallbackInfo__Get(self, index)).?;
    }

    pub fn isolate(self: @This()) Isolate {
        return .{ .handle = e.v8__FunctionCallbackInfo__GetIsolate(self).? };
    }

    /// `true` when the function was invoked with `new`.
    pub fn isConstructCall(self: @This()) bool {
        return e.v8__FunctionCallbackInfo__IsConstructCall(self);
    }

    pub fn this(self: @This()) Object {
        return Object.from_opaque(e.v8__FunctionCallbackInfo__This(self)).?;
    }

    pub fn newTarget(self: @This()) Value {
        return Value.from_opaque(e.v8__FunctionCallbackInfo__NewTarget(self)).?;
    }

    pub fn retval(self: @This()) ReturnValue {
        return .{ .addr = @intFromPtr(e.v8__FunctionCallbackInfo__GetReturnValue(self)) };
    }
};

pub const FunctionCallback = *const fn (FunctionCallbackInfo) callconv(.c) void;

pub const Signature = extern struct {
    pub const Opaque = opaque {};

    handle: *Opaque,
};

pub const ConstructorBehavior = enum(c_int) { Throw, Allow };

pub const SideEffectType = enum(c_int) {
    HasSideEffect,
    HasNoSideEffect,
    HasSideEffectToReceiver,
};

pub const Function = extern struct {

    object: Object,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .object = Object.from_opaque(o) orelse return null,
        };
    }

    pub fn init(
        context: Context,
        callback: FunctionCallback,
        maybe_data: ?Data,
        length: c_int,
        constructor_behavior: ConstructorBehavior,
        side_effect_type: SideEffectType,
    ) Function {
        return Function.from_opaque(e.v8__Function__New(
            context,
            callback,
            if (maybe_data) |v| v.handle else null,
            length,
            constructor_behavior,
            side_effect_type,
        )).?;
    }

    pub fn getName(self: @This()) Value {
        return Value.from_opaque(e.v8__Function__GetName(self)).?;
    }

    pub fn setName(self: @This(), name: String) void {
        e.v8__Function__SetName(self, name);
    }

    pub fn getScriptColumnNumber(self: @This()) c_int {
        return e.v8__Function__GetScriptColumnNumber(self);
    }
    pub fn getScriptLineNumber(self: @This()) c_int {
        return e.v8__Function__GetScriptLineNumber(self);
    }
    fn scriptId(self: Function) c_int {
        return e.v8__Function__ScriptId(self);
    }
    fn getScriptOrigin(self: Function) ScriptOrigin {
        return .from_opaque(e.v8__Function__GetScriptOrigin(self));
    }
};

pub const FunctionTemplate = extern struct {

    pub const Builder = struct {
        data_: ?Data = null,
        signature_: ?Signature = null,
        length_: c_int = 0,
        constructor_behavior_: ConstructorBehavior = .Allow,
        side_effect_type_: SideEffectType = .HasSideEffect,

        pub fn data(self: *@This(), data_: ?Data) *@This() {
            self.data_ = data_;
            return self;
        }

        pub fn signature(self: *@This(), signature_: ?Signature) *@This() {
            self.signature_ = signature_;
            return self;
        }

        pub fn length(self: *@This(), length_: c_int) *@This() {
            self.length_ = length_;
            return self;
        }

        pub fn constructor_behavior(self: *@This(), constructor_behavior_: ConstructorBehavior) *@This() {
            self.constructor_behavior_ = constructor_behavior_;
            return self;
        }

        pub fn side_effect_type(self: *@This(), side_effect_type_: SideEffectType) *@This() {
            self.side_effect_type_ = side_effect_type_;
            return self;
        }

        pub fn build(self: @This(), isolate: Isolate, callback: FunctionCallback, c_functions: []CFunction) FunctionTemplate {
            return .init(isolate, callback, self.data_, self.signature_, self.length_, self.constructor_behavior_, self.side_effect_type_, c_functions);
        }
    };

    template: Template,

    pub fn from_opaque(o: MaybeHandle) @This() {
        return .{
            .template = Template.from_opaque(o).?,
        };
    }

    pub fn init(
        isolate: Isolate,
        callback: FunctionCallback,
        maybe_data: ?Data,
        maybe_signature: ?Signature,
        length: c_int,
        constructor_behavior: ConstructorBehavior,
        side_effect_type: SideEffectType,
        c_functions: []CFunction,
    ) @This() {
        return .from_opaque(e.v8__FunctionTemplate__New(
            isolate.handle,
            callback,
            if (maybe_data) |v| v.handle else null,
            if (maybe_signature) |v| v.handle else null,
            length,
            constructor_behavior,
            side_effect_type,
            @ptrCast(c_functions.ptr),
            c_functions.len,
        ));
    }

    pub fn getFunction(self: @This(), context: Context) ?Function {
        return .from_opaque(e.v8__FunctionTemplate__GetFunction(self, context));
    }
};

pub const ObjectTemplate = extern struct {

    template: Template,

    pub fn initDefault(isolate: Isolate) ?@This() {
        return .{
            .template = Template.from_opaque(e.v8__ObjectTemplate__New__DEFAULT(isolate.handle)) orelse return null,
        };
    }

    pub fn initInstance(self: @This(), context: Context) ?Object {
        return .from_opaque(e.v8__ObjectTemplate__NewInstance(self, context));
    }
};

pub const MicrotaskQueue = struct {
    pub const Opaque = opaque {};

    handle: *Opaque,
};

pub const Context = extern struct {

    data: Data,

    const Self = @This();

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
};

pub const Address = ?*opaque {};

pub const Handle = if (binding.opts.is_direct_handle) Address else *Address;

/// A handle that may be empty. The C ABI uses nullptr for "no handle" in both
/// configurations (see local_to_ptr in binding/support.h). With indirect handles
/// that is an optional pointer; with direct handles `Address` is already nullable,
/// and `?Address` would be an optional of an optional - not a pointer at all.
pub const MaybeHandle = if (binding.opts.is_direct_handle) Handle else ?Handle;

/// How V8 itself spells an empty `Local`/`MaybeLocal`: nullptr normally, but the
/// tagged value 1 (kTaggedNullAddress) with direct handles. Handles returned by the
/// shims are already normalized to null (see binding/support.h); only values that V8
/// hands to a Zig callback, or that a Zig callback returns to V8, use this encoding.
pub const raw_empty_local: usize = if (binding.opts.is_direct_handle) 1 else 0;

/// Encodes a handle for a callback return value or argument V8 will read directly.
pub fn toRawLocal(h: MaybeHandle) usize {
    const bits = @intFromPtr(h);
    return if (bits == 0) raw_empty_local else bits;
}

/// Decodes a `Local`/`MaybeLocal` that V8 passed to a callback.
pub fn fromRawLocal(bits: usize) MaybeHandle {
    return if (bits == raw_empty_local) null else @ptrFromInt(bits);
}

comptime {
    // Local<T> must stay a single pointer-sized value for any of this to hold.
    std.debug.assert(@sizeOf(Handle) == @sizeOf(usize));
}

pub const Global = extern struct {

    handle: Handle,

    pub fn new(isolate: Isolate, handle: Data) @This() {
        return .{
            .handle = e.v8__Global__New(isolate.handle, handle).?,
        };
    }

    pub fn deinit(self: @This()) void {
        e.v8__Global__Reset(self.handle);
    }

    pub fn Of(T: type) type {
        return struct {
            inner: Global,

            pub fn from_global(global: Global) @This() {
                return .{
                    .inner = global,
                };
            }

            pub fn new(isolate: Isolate, data: T) @This() {
                return .{
                    .inner = Global.new(isolate, data),
                };
            }

            pub fn deref(self: @This()) T {
                return .from_opaque(self.inner.handle);
            }

            pub fn deinit(self: @This()) void {
                self.inner.deinit();
            }
        };
    }
};

pub const Weak = extern struct {
    handle: Handle,
};

pub const Data = extern struct {
    handle: Handle,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .handle = @ptrCast(o orelse return null),
        };
    }
};

pub const Value = extern struct {

    data: Data,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .data = Data.from_opaque(o) orelse return null,
        };
    }

    pub fn toString(self: @This(), context: Context) ?String {
        return String.from_opaque(e.v8__Value__ToString(self, context));
    }

    pub fn isNumber(self: @This()) bool {
        return e.v8__Value__IsNumber(self);
    }

    pub fn u32Value(self: @This(), context: Context) ?u32 {
        var out: support.Maybe(u32) = undefined;
        e.v8__Value__Uint32Value(self, context, &out);
        return out.as_optional();
    }

    pub fn i32Value(self: @This(), context: Context) ?i32 {
        var out: support.Maybe(i32) = undefined;
        e.v8__Value__Int32Value(self, context, &out);
        return out.as_optional();
    }
};

pub const Object = extern struct {

    value: Value,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .value = Value.from_opaque(o) orelse return null,
        };
    }

    pub fn init(isolate: Isolate) Object {
        return from_opaque(e.v8__Object__New(isolate.handle)).?;
    }

    /// `prototype` is a required object, or JS `null` (`Primitive.initNull`) for none;
    /// V8 rejects an empty handle.
    pub fn initWithProperties(
        isolate: Isolate,
        prototype: Value,
        names: []const Name,
        values: []const Value,
    ) Object {
        std.debug.assert(names.len == values.len);
        return from_opaque(e.v8__Object__New__with_prototype_and_properties(
            isolate.handle,
            prototype,
            // Name/Value are one-pointer wrappers, layout-identical to a handle array.
            @ptrCast(names.ptr),
            @ptrCast(values.ptr),
            names.len,
        )).?;
    }

    pub fn get(self: Object, context: Context, key: Value) ?Value {
        return Value.from_opaque(e.v8__Object__Get(self, context, key));
    }

    pub fn getWithReceiver(self: Object, context: Context, key: Value, receiver: Object) ?Value {
        return Value.from_opaque(e.v8__Object__GetWithReceiver(self, context, key, receiver));
    }

    pub fn getIndex(self: Object, context: Context, index: u32) ?Value {
        return Value.from_opaque(e.v8__Object__GetIndex(self, context, index));
    }

    pub fn getAlignedPointerFromInternalField(self: Object, index: c_int) ?*anyopaque {
        return e.v8__Object__GetAlignedPointerFromInternalField(self, index);
    }

    pub fn setAlignedPointerInInternalField(self: Object, index: c_int, value: ?*anyopaque) void {
        e.v8__Object__SetAlignedPointerInInternalField(self, index, value);
    }

    pub fn isApiWrapper(self: Object) bool {
        return e.v8__Object__IsApiWrapper(self);
    }

    pub fn getPrototype(self: Object) ?Value {
        return Value.from_opaque(e.v8__Object__GetPrototype(self));
    }

    pub fn set(self: Object, context: Context, key: Value, value: Value) ?bool {
        return e.v8__Object__Set(self, context, key, value).as_optional();
    }

    pub fn setWithReceiver(self: Object, context: Context, key: Value, value: Value, receiver: Object) ?bool {
        return e.v8__Object__SetWithReceiver(self, context, key, value, receiver).as_optional();
    }

    pub fn setIndex(self: Object, context: Context, index: u32, value: Value) ?bool {
        return e.v8__Object__SetIndex(self, context, index, value).as_optional();
    }

    pub fn setPrototype(self: Object, context: Context, prototype: Value) ?bool {
        return e.v8__Object__SetPrototype(self, context, prototype).as_optional();
    }

    pub fn getConstructorName(self: Object) String {
        return String.from_opaque(e.v8__Object__GetConstructorName(self)).?;
    }

    pub fn createDataProperty(self: Object, context: Context, key: Name, value: Value) ?bool {
        return e.v8__Object__CreateDataProperty(self, context, key, value).as_optional();
    }

    pub fn defineOwnProperty(self: Object, context: Context, key: Name, value: Value, attr: PropertyAttribute) ?bool {
        return e.v8__Object__DefineOwnProperty(self, context, key, value, attr).as_optional();
    }

    pub fn defineProperty(self: Object, context: Context, key: Name, desc: *PropertyDescriptor) ?bool {
        return e.v8__Object__DefineProperty(self, context, key, desc).as_optional();
    }

    pub fn setAccessor(
        self: Object,
        context: Context,
        key: Name,
        getter: AccessorNameGetterCallback,
        setter: ?AccessorNameSetterCallback,
        data: ?Value,
        attr: PropertyAttribute,
    ) ?bool {
        return e.v8__Object__SetAccessor(
            self,
            context,
            key,
            getter,
            setter,
            if (data) |v| v.data.handle else null,
            attr,
        ).as_optional();
    }

    pub fn getIdentityHash(self: Object) c_int {
        return e.v8__Object__GetIdentityHash(self);
    }

    pub fn getCreationContext(self: Object) ?Context {
        return Context.from_opaque(e.v8__Object__GetCreationContext(self));
    }
};

pub const External = extern struct {

    value: Value,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .value = Value.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, ptr: ?*anyopaque) @This() {
        return External.from_opaque(e.v8__External__New(isolate.handle, ptr)).?;
    }

    pub fn pointer(self: @This()) ?*anyopaque {
        return e.v8__External__Value(self);
    }
};

pub const Primitive = extern struct {
    value: Value,

    /// The JavaScript `null` value.
    pub fn initNull(isolate: Isolate) Primitive {
        return from_opaque(e.v8__Null(isolate.handle)).?;
    }

    /// The JavaScript `undefined` value.
    pub fn initUndefined(isolate: Isolate) Primitive {
        return from_opaque(e.v8__Undefined(isolate.handle)).?;
    }

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .value = Value.from_opaque(o) orelse return null,
        };
    }
};

pub const Promise = extern struct {

    object: Object,

    pub const PromiseState = enum(c_int) { Pending, Fulfilled, Rejected };

    pub const Resolver = extern struct {

        object: Object,

        pub fn from_opaque(o: MaybeHandle) ?@This() {
            return .{ .object = Object.from_opaque(o) orelse return null };
        }

        pub fn init(context: Context) ?@This() {
            return .from_opaque(e.v8__Promise__Resolver__New(context));
        }

        pub fn getPromise(self: @This()) Promise {
            return Promise.from_opaque(e.v8__Promise__Resolver__GetPromise(self)).?;
        }

        pub fn resolve(self: @This(), context: Context, value: Value) ?bool {
            return e.v8__Promise__Resolver__Resolve(self, context, value).as_optional();
        }

        pub fn reject(self: @This(), context: Context, value: Value) ?bool {
            return e.v8__Promise__Resolver__Reject(self, context, value).as_optional();
        }
    };

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .object = Object.from_opaque(o) orelse return null };
    }

    pub fn result(self: @This()) Value {
        return Value.from_opaque(e.v8__Promise__Result(self)).?;
    }

    pub fn state(self: @This()) PromiseState {
        return e.v8__Promise__State(self);
    }
};

pub const Numeric = extern struct {
    primitive: Primitive,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .primitive = Primitive.from_opaque(o) orelse return null };
    }
};

pub const Number = extern struct {

    numeric: Numeric,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .numeric = Numeric.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, value: f64) @This() {
        return @This().from_opaque(e.v8__Number__New(isolate.handle, value)).?;
    }

    pub fn initInt(isolate: Isolate, value: i32) @This() {
        return @This().from_opaque(e.v8__Number__NewInt(isolate.handle, value)).?;
    }

    pub fn initUInt(isolate: Isolate, value: u32) @This() {
        return @This().from_opaque(e.v8__Number__NewUInt(isolate.handle, value)).?;
    }

    pub fn Value(self: @This()) f64 {
        return e.v8__Number__Value(self);
    }
};

pub const Name = extern struct {
    primitive: Primitive,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .primitive = Primitive.from_opaque(o) orelse return null };
    }
};

pub const String = extern struct {
    pub const NewStringType = enum(c_int) { Normal, Internalized };

    pub const WriteFlags = struct {
        pub const None = @as(c_int, 0);
        pub const NullTermination = @as(c_int, 1) << 0;
        pub const PreserveAsciiNull = @as(c_int, 1) << 1;
        pub const ReplaceInvalidUtf8 = @as(c_int, 1) << 2;
    };


    name: Name,

    const Self = @This();

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .name = Name.from_opaque(o) orelse return null };
    }

    pub fn initUtf8(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewFromUtf8(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn initOneByte(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewFromOneByte(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn initTwoByte(isolate: Isolate, str: []const u16) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewFromTwoByte(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn initOneByteStatic(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewExternalOneByteStatic(isolate.handle, str.ptr, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn initTwoByteStatic(isolate: Isolate, str: []const u16) Self {
        return .{
            .name = Name.from_opaque(e.v8__String__NewExternalTwoByteStatic(isolate.handle, str.ptr, @as(c_int, @intCast(str.len)))).?,
        };
    }

    pub fn len(self: Self) c_int {
        return e.v8__String__Length(self);
    }

    pub fn lenUtf8(self: Self, isolate: Isolate) usize {
        return e.v8__String__Utf8Length(self, isolate.handle);
    }

    pub fn writeUtf8(self: Self, isolate: Isolate, buf: []u8) usize {
        const flags = WriteFlags.ReplaceInvalidUtf8;
        return e.v8__String__WriteUtf8(self, isolate.handle, buf.ptr, buf.len, flags, null);
    }
};

pub const Module = extern struct {
    data: Data,

    // todo
};

pub const ArrayBuffer = extern struct {
    object: Object,

    pub const Allocator = extern struct {
        pub const Opaque = opaque {};

        handle: *Opaque,

        pub fn initDefault() @This() {
            return .{
                .handle = e.v8__ArrayBuffer__Allocator__NewDefaultAllocator().?,
            };
        }

        pub fn deinit(self: @This()) void {
            e.v8__ArrayBuffer__Allocator__DELETE(self.handle);
        }
    };
};

pub const Script = extern struct {

    data: Data,

    const Self = @This();

    pub fn from_opaque(o: MaybeHandle) ?Self {
        return .{
            .data = Data.from_opaque(o) orelse return null,
        };
    }

    pub fn compile(context: Context, source: String, origin: ?ScriptOrigin) ?Self {
        const ptr = if (origin) |o| &o.inner else null;
        return @This().from_opaque(e.v8__Script__Compile(context, source, ptr));
    }

    pub fn run(self: Self, context: Context) ?Value {
        return Value.from_opaque(e.v8__Script__Run(self, context));
    }
};

pub const TryCatch = struct {
    pub const Opaque = [binding.sizes.TryCatch]u8;


    inner: Opaque,

    const Self = @This();

    pub fn init(self: *Self, isolate: Isolate) void {
        e.v8__TryCatch__CONSTRUCT(&self.inner, isolate.handle);
    }

    pub fn deinit(self: *Self) void {
        e.v8__TryCatch__DESTRUCT(&self.inner);
    }

    pub fn hasCaught(self: *const Self) bool {
        return e.v8__TryCatch__HasCaught(&self.inner);
    }

    pub fn canContinue(self: *const Self) bool {
        return e.v8__TryCatch__CanContinue(&self.inner);
    }

    pub fn hasTerminated(self: *const Self) bool {
        return e.v8__TryCatch__HasTerminated(&self.inner);
    }

    pub fn getException(self: *const Self) ?Value {
        const handle = e.v8__TryCatch__Exception(&self.inner) orelse return null;
        return .from_opaque(handle);
    }

    pub fn getStackTrace(self: *const Self, context: Context) ?Value {
        const handle = e.v8__TryCatch__StackTrace(&self.inner, context) orelse return null;
        return .from_opaque(handle);
    }

    pub fn getMessage(self: *const Self) ?Message {
        const handle = e.v8__TryCatch__Message(&self.inner) orelse return null;
        return .{ .handle = handle };
    }

    pub fn reset(self: *Self) void {
        e.v8__TryCatch__Reset(&self.inner);
    }

    pub fn reThrow(self: *Self) ?Value {
        const handle = e.v8__TryCatch__ReThrow(&self.inner) orelse return null;
        return .from_opaque(handle);
    }

    pub fn isVerbose(self: *const Self) bool {
        return e.v8__TryCatch__IsVerbose(&self.inner);
    }

    pub fn setVerbose(self: *Self, value: bool) void {
        e.v8__TryCatch__SetVerbose(&self.inner, value);
    }

    pub fn setCaptureMessage(self: *Self, value: bool) void {
        e.v8__TryCatch__SetCaptureMessage(&self.inner, value);
    }
};

pub const StackFrame = struct {
    pub const Opaque = opaque {};


    handle: *const Opaque,

    const Self = @This();

    pub fn getLineNumber(self: Self) c_int {
        return e.v8__StackFrame__GetLineNumber(self.handle);
    }

    pub fn getColumn(self: Self) c_int {
        return e.v8__StackFrame__GetColumn(self.handle);
    }

    pub fn getScriptId(self: Self) c_int {
        return e.v8__StackFrame__GetScriptId(self.handle);
    }

    pub fn getScriptName(self: Self) ?String {
        if (e.v8__StackFrame__GetScriptName(self.handle)) |ptr| {
            return String.from_opaque(ptr);
        }
        return null;
    }

    pub fn getScriptNameOrSourceUrl(self: Self) ?String {
        if (e.v8__StackFrame__GetScriptNameOrSourceURL(self.handle)) |ptr| {
            return String.from_opaque(ptr);
        }
        return null;
    }

    pub fn getFunctionName(self: Self) ?String {
        if (e.v8__StackFrame__GetFunctionName(self.handle)) |ptr| {
            return String.from_opaque(ptr);
        }
        return null;
    }

    pub fn isEval(self: Self) bool {
        return e.v8__StackFrame__IsEval(self.handle);
    }

    pub fn isConstructor(self: Self) bool {
        return e.v8__StackFrame__IsConstructor(self.handle);
    }

    pub fn isWasm(self: Self) bool {
        return e.v8__StackFrame__IsWasm(self.handle);
    }

    pub fn isUserJavascript(self: Self) bool {
        return e.v8__StackFrame__IsUserJavaScript(self.handle);
    }
};

pub const StackTrace = struct {
    pub const Opaque = opaque {};


    handle: *const Opaque,

    const Self = @This();

    pub fn getFrameCount(self: Self) c_int {
        return e.v8__StackTrace__GetFrameCount(self.handle);
    }

    pub fn getFrame(self: Self, isolate: Isolate, index: u32) StackFrame {
        return .{
            .handle = e.v8__StackTrace__GetFrame(self.handle, isolate.handle, index).?,
        };
    }

    pub fn getCurrentStackTrace(isolate: Isolate, frame_limit: c_int) StackTrace {
        return .{
            .handle = e.v8__StackTrace__CurrentStackTrace(isolate.handle, frame_limit).?,
        };
    }

    pub fn getCurrentScriptNameOrSourceUrl(isolate: Isolate) ?String {
        if (e.v8__StackTrace__CurrentScriptNameOrSourceURL(isolate.handle)) |ptr| {
            return String.from_opaque(ptr);
        }
        return null;
    }
};

pub const Message = struct {
    pub const Opaque = opaque {};


    handle: *const Opaque,

    const Self = @This();

    pub fn get(self: Self) String {
        return String.from_opaque(e.v8__Message__Get(self.handle)).?;
    }

    pub fn getSourceLine(self: Self, context: Context) ?String {
        const ptr = e.v8__Message__GetSourceLine(self.handle, context);
        return .from_opaque(ptr);
    }

    pub fn getScriptResourceName(self: Self) Value {
        return Value.from_opaque(e.v8__Message__GetScriptResourceName(self.handle)).?;
    }

    pub fn getLineNumber(self: Self, context: Context) ?c_uint {
        const res = e.v8__Message__GetLineNumber(self.handle, context);
        if (res != -1) return @intCast(res);
        return null;
    }

    pub fn getStartColumn(self: Self) ?c_uint {
        const res = e.v8__Message__GetStartColumn(self.handle);
        if (res != -1) return @intCast(res);
        return null;
    }

    pub fn getEndColumn(self: Self) ?c_uint {
        const res = e.v8__Message__GetEndColumn(self.handle);
        if (res != -1) return @intCast(res);
        return null;
    }

    pub fn getStackTrace(self: Self) ?StackTrace {
        if (e.v8__Message__GetStackTrace(self.handle)) |ptr| {
            return .{ .handle = ptr };
        }
        return null;
    }

    pub fn getStartPosition(self: Self) i32 {
        return e.v8__Message__GetStartPosition(self.handle);
    }

    pub fn getEndPosition(self: Self) i32 {
        return e.v8__Message__GetEndPosition(self.handle);
    }

    pub fn getWasmFunctionIndex(self: Self) i32 {
        return e.v8__Message__GetWasmFunctionIndex(self.handle);
    }

    pub fn getErrorLevel(self: Self) i32 {
        return e.v8__Message__ErrorLevel(self.handle);
    }

    pub fn isSharedCrossOrigin(self: Self) bool {
        return e.v8__Message__IsSharedCrossOrigin(self.handle);
    }
};

pub const ScriptOrigin = struct {
    pub const Opaque = [binding.sizes.ScriptOrigin]u8;

    const Self = @This();


    inner: Opaque,

    pub fn initDefault(resource_name: Value) Self {
        return init(
            resource_name,
            0,
            0,
            false,
            -1,
            null,
            false,
            false,
            false,
            null,
        );
    }

    pub fn init(
        resource_name: Value,
        resource_line_offset: c_int,
        resource_column_offset: c_int,
        resource_is_shared_cross_origin: bool,
        script_id: c_int,
        source_map_url: ?Value,
        resource_is_opaque: bool,
        is_wasm: bool,
        is_module: bool,
        host_defined_options: ?Data,
    ) Self {
        var place: ScriptOrigin = undefined;
        e.v8__ScriptOrigin__CONSTRUCT(
            &place.inner,
            resource_name,
            resource_line_offset,
            resource_column_offset,
            resource_is_shared_cross_origin,
            script_id,
            if (source_map_url) |v| v.data.handle else null,
            resource_is_opaque,
            is_wasm,
            is_module,
            if (host_defined_options) |v| v.handle else null,
        );
        return place;
    }
};

pub const HeapStatistics = extern struct {
    total_heap_size: usize,
    total_heap_size_executable: usize,
    total_physical_size: usize,
    total_available_size: usize,
    used_heap_size: usize,
    heap_size_limit: usize,
    malloced_memory: usize,
    external_memory: usize,
    peak_malloced_memory: usize,
    does_zap_garbage: bool,
    number_of_native_contexts: usize,
    number_of_detached_contexts: usize,
    total_global_handles_size: usize,
    used_global_handles_size: usize,
    total_allocated_bytes: u64,
};

pub const MicrotasksPolicy = enum(u32) {
    Explicit = 0,
    Scoped = 1,
    Auto = 2,
};

// Zig only analyzes what is used, so reference every declaration explicitly:
// this is what proves the wrappers still match the generated externs.
/// Zig only analyzes what is used, so reference every declaration of `T` and of
/// the types nested in it (depth-limited: wrappers alias themselves via `Self`).
fn refAllNested(comptime T: type, comptime depth: u8) void {
    if (depth == 0) return;
    switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => {},
        else => return,
    }
    std.testing.refAllDecls(T);
    inline for (comptime std.meta.declarations(T)) |decl| {
        const value = @field(T, decl);
        if (@TypeOf(value) == type) refAllNested(value, depth - 1);
    }
}

test {
    _ = @import("test.zig");
}

test "wrappers type-check against the generated externs" {
    std.testing.refAllDecls(e);
    refAllNested(@This(), 3);
}
