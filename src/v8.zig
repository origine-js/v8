const std = @import("std");
const binding = @import("./binding.zig");

const support = struct {
    pub const MaybeBool = enum(c_int) {
        JustFalse = 0,
        JustTrue = 1,
        Nothing = 2,

        pub fn as_maybe_bool(self: @This()) ?bool {
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

    extern fn v8__Platform__NewDefaultPlatform(thread_pool_size: c_int, idle_task_support: bool) ?*Opaque;
    extern fn v8__Platform__DELETE(handle: *Opaque) void;
    extern fn v8__Platform__PumpMessageLoop(platform: *Opaque, isolate: *Isolate.Opaque, wait_for_work: bool) bool;

    handle: *Opaque,

    const Self = @This();

    /// Returns a new instance of the default v8::Platform implementation.
    /// |thread_pool_size| is the number of worker threads to allocate for background jobs.
    /// If 0, a suitable default based on the processors will be chosen.
    pub fn initDefault(thread_pool_size: u32, idle_task_support: bool) Self {
        return .{
            .handle = v8__Platform__NewDefaultPlatform(@as(c_int, @intCast(thread_pool_size)), idle_task_support).?,
        };
    }

    pub fn deinit(self: Self) void {
        v8__Platform__DELETE(self.handle);
    }

    /// Pumps the message loop for the given isolate.
    pub fn pumpMessageLoop(self: Self, isolate: Isolate, wait_for_work: bool) bool {
        return v8__Platform__PumpMessageLoop(self.handle, isolate.handle, wait_for_work);
    }
};

pub const V8 = struct {
    extern fn v8__V8__Initialize() void;
    extern fn v8__V8__InitializePlatform(platform: *Platform.Opaque) void;
    extern fn v8__V8__InitializeICU() void;
    extern fn v8__V8__Dispose() void;
    extern fn v8__V8__DisposePlatform() void;

    /// Initializes V8. This function needs to be called before the first Isolate is created.
    pub fn initialize() void {
        v8__V8__Initialize();
    }

    /// Sets the v8::Platform to use. This should be invoked before V8 is initialized.
    pub fn initializePlatform(platform: Platform) void {
        v8__V8__InitializePlatform(platform.handle);
    }

    /// Initializes the ICU bundled with v8.
    pub fn initializeICU() void {
        v8__V8__InitializeICU();
    }

    /// Releases any resources used by v8 and stops any utility thread that may be running.
    pub fn dispose() void {
        v8__V8__Dispose();
    }

    /// Clears all references to the v8::Platform. This should be invoked after V8 was disposed.
    pub fn disposePlatform() void {
        v8__V8__DisposePlatform();
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
    // todo
};

pub const HostInitializeImportMetaObjectCallback = *const fn (Context, Module, Object) void;
pub const HostImportModuleDynamicallyCallback = *const fn (Context, host_defined_options: Data, resource_name: Value, specifier: String, import_attributes: FixedArray) void;

pub const Isolate = extern struct {
    pub const Opaque = opaque {};

    extern fn v8__Isolate__New(params: *const CreateParams) ?*Opaque;
    extern fn v8__Isolate__Enter(handle: *Opaque) void;
    extern fn v8__Isolate__Exit(handle: *Opaque) void;
    extern fn v8__Isolate__Dispose(handle: *Opaque) void;
    extern fn v8__Isolate__GetCurrentContext(handle: *Opaque) ?*Address;
    extern fn v8__Isolate__ThrowException(handle: *Opaque, value: Value) ?*Address;
    extern fn v8__Isolate__SetData(handle: *Opaque, slot: u32, data: ?*anyopaque) void;
    extern fn v8__Isolate__GetData(handle: *Opaque, slot: u32) ?*anyopaque;
    extern fn v8__Isolate__PerformMicrotaskCheckpoint(handle: *Opaque) void;
    extern fn v8__Isolate__GetMicrotasksPolicy(handle: *Opaque) MicrotasksPolicy;
    extern fn v8__Isolate__SetMicrotasksPolicy(handle: *Opaque, policy: MicrotasksPolicy) void;
    extern fn v8__Isolate__LowMemoryNotification(handle: *Opaque) void;
    extern fn v8__Isolate__TerminateExecution(handle: *Opaque) void;
    extern fn v8__Isolate__IsExecutionTerminating(handle: *Opaque) bool;
    extern fn v8__Isolate__CancelTerminateExecution(handle: *Opaque) void;
    extern fn v8__Isolate__SetCaptureStackTraceForUncaughtExceptions(handle: *Opaque, capture: bool, frame_limit: c_int) void;
    extern fn v8__Isolate__GetHeapStatistics(handle: *Opaque, statistics: *HeapStatistics) void;

    pub const CreateParams = extern struct {
        pub extern fn v8__Isolate__CreateParams__CONSTRUCT(ptr: *@This()) void;

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
        embedder_wrapper_type_index: c_int = -1,
        embedder_wrapper_object_index: c_int = -1,
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
            v8__Isolate__CreateParams__CONSTRUCT(&params);
            return params;
        }
    };

    handle: *Opaque,

    const Self = @This();

    pub fn init(params: *const CreateParams) Self {
        return .{
            .handle = v8__Isolate__New(params).?,
        };
    }

    pub fn deinit(self: Self) void {
        v8__Isolate__Dispose(self.handle);
    }

    pub fn enter(self: Self) void {
        v8__Isolate__Enter(self.handle);
    }

    pub fn exit(self: Self) void {
        v8__Isolate__Exit(self.handle);
    }

    pub fn getCurrentContext(self: Self) Context {
        return .{
            .data = .from_opaque(v8__Isolate__GetCurrentContext(self.handle)),
        };
    }

    pub fn throwException(self: Self, value: Value) Value {
        return .from_opaque(v8__Isolate__ThrowException(self.handle, value));
    }

    pub fn setData(self: Self, slot: u32, data: ?*anyopaque) void {
        v8__Isolate__SetData(self.handle, slot, data);
    }

    pub fn getData(self: Self, slot: u32) ?*anyopaque {
        return v8__Isolate__GetData(self.handle, slot);
    }

    pub fn performMicrotasksCheckpoint(self: Self) void {
        v8__Isolate__PerformMicrotaskCheckpoint(self.handle);
    }

    pub fn getMicrotasksPolicy(self: Self) MicrotasksPolicy {
        return v8__Isolate__GetMicrotasksPolicy(self.handle);
    }

    pub fn setMicrotasksPolicy(self: Self, policy: MicrotasksPolicy) void {
        v8__Isolate__SetMicrotasksPolicy(self.handle, policy);
    }

    pub fn lowMemoryNotification(self: Self) void {
        v8__Isolate__LowMemoryNotification(self.handle);
    }

    pub fn terminateExecution(self: Self) void {
        v8__Isolate__TerminateExecution(self.handle);
    }

    pub fn isExecutionTerminating(self: Self) bool {
        return v8__Isolate__IsExecutionTerminating(self.handle);
    }

    pub fn cancelTerminateExecution(self: Self) void {
        v8__Isolate__CancelTerminateExecution(self.handle);
    }

    pub fn getHeapStatistics(self: Self) HeapStatistics {
        var res: HeapStatistics = undefined;
        v8__Isolate__GetHeapStatistics(self.handle, &res);
        return res;
    }

    pub fn setCaptureStackTraceForUncaughtExceptions(self: Self, capture: bool, frame_limit: u32) void {
        v8__Isolate__SetCaptureStackTraceForUncaughtExceptions(self.handle, capture, @as(c_int, @intCast(frame_limit)));
    }
};

pub const HandleScope = struct {
    pub const Opaque = [binding.sizes.HandleScope]u8;

    extern fn v8__HandleScope__CONSTRUCT(ptr: *Opaque, isolate: *Isolate.Opaque) void;
    extern fn v8__HandleScope__DESTRUCT(ptr: *Opaque) void;

    inner: Opaque,

    const Self = @This();

    pub fn init(self: *Self, isolate: Isolate) void {
        v8__HandleScope__CONSTRUCT(&self.inner, isolate.handle);
    }

    pub fn deinit(self: *Self) void {
        v8__HandleScope__DESTRUCT(&self.inner);
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
    flags: packed struct {
        AllowSharedBit: bool,
        EnforceRangeBit: bool,
        ClampBit: bool,
        IsRestrictedBit: bool,
        _unused: u28 = 0,
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
    extern fn v8__ReturnValue__Value__Set(self: *ReturnValue, value: Value) void;
    extern fn v8__ReturnValue__Value__Set__Bool(self: *ReturnValue, i: bool) void;
    extern fn v8__ReturnValue__Value__Set__Int32(self: *ReturnValue, i: i32) void;
    extern fn v8__ReturnValue__Value__Set__Uint32(self: *ReturnValue, i: u32) void;
    extern fn v8__ReturnValue__Value__Set__Double(self: *ReturnValue, i: f64) void;
    extern fn v8__ReturnValue__Value__SetNull(self: *ReturnValue) void;
    extern fn v8__ReturnValue__Value__SetUndefined(self: *ReturnValue) void;
    extern fn v8__ReturnValue__Value__SetEmptyString(self: *ReturnValue) void;
    extern fn v8__ReturnValue__Value__Get(self: *const ReturnValue) ?*Address;

    handle: *Address,

    pub fn set(self: *@This(), value: Value) void {
        v8__ReturnValue__Value__Set(self, value);
    }

    pub fn setBool(self: *@This(), i: bool) void {
        v8__ReturnValue__Value__Set__Bool(self, i);
    }

    pub fn setInt32(self: *@This(), i: i32) void {
        v8__ReturnValue__Value__Set__Int32(self, i);
    }

    pub fn setUint32(self: *@This(), i: u32) void {
        v8__ReturnValue__Value__Set__Uint32(self, i);
    }

    pub fn setDouble(self: *@This(), i: f64) void {
        v8__ReturnValue__Value__Set__Double(self, i);
    }

    pub fn setNull(self: *@This()) void {
        v8__ReturnValue__Value__SetNull(self);
    }

    pub fn setUndefined(self: *@This()) void {
        v8__ReturnValue__Value__SetUndefined(self);
    }

    pub fn setEmptyString(self: *@This()) void {
        v8__ReturnValue__Value__SetEmptyString(self);
    }

    pub fn get(self: *const @This()) ?Value {
        return Value.from_opaque_maybe(v8__ReturnValue__Value__Get(self));
    }
};

pub const PropertyCallbackInfo = extern struct {
    pub const Opaque = [binding.sizes.PropertyCallbackInfo]u8;

    extern fn v8__PropertyCallbackInfo__GetIsolate(self: *const PropertyCallbackInfo) *Isolate.Opaque;
    extern fn v8__PropertyCallbackInfo__Data(self: *const PropertyCallbackInfo) ?*Address;
    extern fn v8__PropertyCallbackInfo__This(self: *const PropertyCallbackInfo) ?*Address;
    extern fn v8__PropertyCallbackInfo__Holder(self: *const PropertyCallbackInfo) ?*Address;
    extern fn v8__PropertyCallbackInfo__GetReturnValue(self: *const PropertyCallbackInfo) *Address;
    extern fn v8__PropertyCallbackInfo__ShouldThrowOnError(self: *const PropertyCallbackInfo) bool;

    inner: Opaque,

    pub fn isolate(self: *const @This()) Isolate {
        return .{ .handle = v8__PropertyCallbackInfo__GetIsolate(self) };
    }

    pub fn data(self: *const @This()) ?Data {
        return Data.from_opaque_maybe(v8__PropertyCallbackInfo__Data(self));
    }

    pub fn this(self: *const @This()) Object {
        return Object.from_opaque(v8__PropertyCallbackInfo__This(self));
    }

    pub fn holder(self: *const @This()) Object {
        return Object.from_opaque(v8__PropertyCallbackInfo__Holder(self));
    }

    pub fn retval(self: *const @This()) ReturnValue {
        return .{ .addr = v8__PropertyCallbackInfo__GetReturnValue(self) };
    }

    pub fn shouldThrowOnError(self: *const @This()) bool {
        return v8__PropertyCallbackInfo__ShouldThrowOnError(self);
    }

    comptime {
        std.debug.assert(@sizeOf(PropertyCallbackInfo) == binding.sizes.PropertyCallbackInfo);
    }
};

pub const AccessorNameGetterCallback = *const fn (Name, *const PropertyCallbackInfo) callconv(.c) void;
pub const AccessorNameSetterCallback = *const fn (Name, Value, *const PropertyCallbackInfo) callconv(.c) void;

// https://github.com/denoland/rusty_v8/blob/4d9f92762600fd3475a5632005ecf3721514b8d4/src/property_attribute.rs#L5
pub const PropertyDescriptor = struct {
    pub const Opaque = [binding.sizes.PropertyDescriptor]u8;
    inner: Opaque,

    extern fn v8__PropertyDescriptor__CONSTRUCT(ptr: *Opaque) void;
    extern fn v8__PropertyDescriptor__CONSTRUCT__Value(ptr: *Opaque, value: Value) void;
    extern fn v8__PropertyDescriptor__CONSTRUCT__Value_Writable(ptr: *Opaque, value: Value, writable: bool) void;
    extern fn v8__PropertyDescriptor__CONSTRUCT__Get_Set(ptr: *Opaque, get: Value, set: Value) void;
    extern fn v8__PropertyDescriptor__DESTRUCT(ptr: *Opaque) void;

    pub fn init() PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        v8__PropertyDescriptor__CONSTRUCT(&self.inner);
        return self;
    }

    pub fn initValue(value: Value, writable: ?bool) PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        if (writable) |w| {
            v8__PropertyDescriptor__CONSTRUCT__Value_Writable(&self.inner, value, w);
        } else {
            v8__PropertyDescriptor__CONSTRUCT__Value(&self.inner, value);
        }
        return self;
    }

    pub fn initGetSet(get: Value, set: Value) PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        v8__PropertyDescriptor__CONSTRUCT__Get_Set(&self.inner, get, set);
        return self;
    }

    pub fn deinit(self: *PropertyDescriptor) void {
        v8__PropertyDescriptor__DESTRUCT(&self.inner);
    }
};

pub const PropertyAttribute = packed struct(u32) {
    ReadOnly: bool = false,
    DontEnum: bool = false,
    DontDelete: bool = false,
    _unused: u29 = 0,
};

pub const Template = extern struct {
    extern fn v8__Template__Set(self: Template, key: Name, value: Data, attr: PropertyAttribute) void;

    data: Data,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{ .data = .from_opaque(o) };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .data = Data.from_opaque_maybe(o) orelse return null };
    }

    pub fn set(self: @This(), key: Name, value: Data, attr: PropertyAttribute) void {
        v8__Template__Set(self, key, value, attr);
    }
};

pub const FunctionCallbackInfo = extern struct {
    extern fn v8__FunctionCallbackInfo__Data(this: *const FunctionCallbackInfo) ?*Address;

    implicit_args: *[binding.consts.FunctionCallbackInfo_kArgsLength]Address,
    values: [*]Address,
    length: c_int,

    pub const ImplicitArg = enum(i32) {
        HolderIndex = 0,
        IsolateIndex = 1,
        ContextIndex = 2,
        ReturnValueIndex = 3,
        TargetIndex = 4,
        NewTargetIndex = 5,
        ArgsLength = 6,
        _,
    };

    pub fn data(self: *const @This()) ?Data {
        return Data.from_opaque_maybe(v8__FunctionCallbackInfo__Data(self));
    }

    pub fn get_arg(self: *const @This(), index: c_int) Value {
        std.debug.assert(index >= 0 and index < self.length);
        return .from_opaque(&self.values[@as(usize, @intCast(index))]);
    }

    pub fn isolate(self: *const @This()) Isolate {
        return .{ .handle = @ptrCast(self.get_implicit_arg(.IsolateIndex).?) };
    }

    fn get_implicit_arg(self: *const @This(), index: ImplicitArg) Address {
        return self.implicit_args[@as(usize, @intCast(@intFromEnum(index)))];
    }

    fn get_implicit_arg_ptr(self: *const @This(), index: ImplicitArg) *Address {
        return &self.implicit_args[@as(usize, @intCast(@intFromEnum(index)))];
    }

    pub fn retval(self: *const @This()) ReturnValue {
        return .{ .handle = self.get_implicit_arg_ptr(.ReturnValueIndex) };
    }

    comptime {
        std.debug.assert(@sizeOf(@This()) == binding.sizes.FunctionCallbackInfo);
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
    extern fn v8__Function__Call(self: Function, context: Context, recv: Value, argc: c_int, argv: [*]Value) ?*Address;
    extern fn v8__Function__New(
        context: Context,
        callback: FunctionCallback,
        maybe_data: ?*Address,
        length: c_int,
        constructor_behavior: ConstructorBehavior,
        side_effect_type: SideEffectType,
    ) ?*Address;
    extern fn v8__Function__GetName(self: Function) ?*Address;
    extern fn v8__Function__SetName(self: Function, name: String) void;
    extern fn v8__Function__GetScriptColumnNumber(self: Function) c_int;
    extern fn v8__Function__GetScriptLineNumber(self: Function) c_int;
    extern fn v8__Function__ScriptId(self: Function) c_int;
    extern fn v8__Function__GetScriptOrigin(self: Function) *Address;

    object: Object,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .object = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{
            .object = Object.from_opaque_maybe(o) orelse return null,
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
        return .from_opaque_maybe(v8__Function__New(
            context,
            callback,
            if (maybe_data) |v| v.handle else null,
            length,
            constructor_behavior,
            side_effect_type,
        ));
    }

    pub fn getName(self: @This()) Value {
        return .from_opaque(v8__Function__GetName(self));
    }

    pub fn setName(self: @This(), name: String) void {
        v8__Function__SetName(self, name);
    }

    pub fn getScriptColumnNumber(self: @This()) c_int {
        return v8__Function__GetScriptColumnNumber(self);
    }
    pub fn getScriptLineNumber(self: @This()) c_int {
        return v8__Function__GetScriptLineNumber(self);
    }
    fn scriptId(self: Function) c_int {
        return v8__Function__ScriptId(self);
    }
    fn getScriptOrigin(self: Function) ScriptOrigin {
        return .from_opaque(v8__Function__GetScriptOrigin(self));
    }
};

pub const FunctionTemplate = extern struct {
    extern fn v8__FunctionTemplate__New(
        isolate: ?*Isolate.Opaque,
        callback: FunctionCallback,
        maybe_data: ?*Address,
        maybe_signature: ?*Signature.Opaque,
        length: c_int,
        constructor_behavior: ConstructorBehavior,
        side_effect_type: SideEffectType,
        c_functions: [*]CFunction,
        c_functions_len: usize,
    ) ?*Address;
    extern fn v8__FunctionTemplate__GetFunction(
        self: FunctionTemplate,
        context: Context,
    ) ?*Address;

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

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .template = Template.from_opaque(o),
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
        return .from_opaque(v8__FunctionTemplate__New(
            isolate.handle,
            callback,
            if (maybe_data) |v| v.handle else null,
            if (maybe_signature) |v| v.handle else null,
            length,
            constructor_behavior,
            side_effect_type,
            c_functions.ptr,
            c_functions.len,
        ));
    }

    pub fn getFunction(self: @This(), context: Context) ?Function {
        return .from_opaque_maybe(v8__FunctionTemplate__GetFunction(self, context));
    }
};

pub const ObjectTemplate = extern struct {
    extern fn v8__ObjectTemplate__New__DEFAULT(isolate: *Isolate.Opaque) ?*Address;
    extern fn v8__ObjectTemplate__NewInstance(self: ObjectTemplate, context: Context) ?*Address;

    template: Template,

    pub fn initDefault(isolate: Isolate) ?@This() {
        return .{
            .template = Template.from_opaque_maybe(v8__ObjectTemplate__New__DEFAULT(isolate.handle)) orelse return null,
        };
    }

    pub fn initInstance(self: @This(), context: Context) ?Object {
        return .from_opaque_maybe(v8__ObjectTemplate__NewInstance(self, context));
    }
};

pub const MicrotaskQueue = struct {
    pub const Opaque = opaque {};

    handle: *Opaque,
};

pub const Context = extern struct {
    extern fn v8__Context__New(isolate: *Isolate.Opaque, global_tmpl: ObjectTemplate, global_obj: ?*Address, microtask_queue: ?*MicrotaskQueue.Opaque) ?*Address;
    extern fn v8__Context__Enter(handle: Context) void;
    extern fn v8__Context__Exit(handle: Context) void;
    extern fn v8__Context__Global(handle: Context) ?*Address;
    extern fn v8__Context__GetEmbedderData(handle: Context, index: c_int) ?*Address;
    extern fn v8__Context__SetEmbedderData(handle: Context, index: c_int, value: *Value) void;

    data: Data,

    const Self = @This();

    pub fn from_opaque(o: ?*Address) Self {
        return .{ .data = Data.from_opaque(o) };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?Self {
        return .{ .data = Data.from_opaque_maybe(o) orelse return null };
    }

    pub fn init(isolate: Isolate, global_tmpl: ?ObjectTemplate, global_obj: ?Value, microtask_queue: ?MicrotaskQueue) Self {
        return .{
            .data = .from_opaque(v8__Context__New(
                isolate.handle,
                global_tmpl orelse ObjectTemplate.initDefault(isolate).?,
                if (global_obj) |v| v.data.handle else null,
                if (microtask_queue) |v| v.handle else null,
            )),
        };
    }

    pub fn enter(self: Self) void {
        v8__Context__Enter(self);
    }

    pub fn exit(self: Self) void {
        v8__Context__Exit(self);
    }

    pub fn getGlobal(self: Self) Object {
        return .{
            .value = .from_opaque(v8__Context__Global(self)),
        };
    }

    pub fn getEmbedderData(self: Self, index: u32) Value {
        return .{
            .data = .from_opaque(v8__Context__GetEmbedderData(self, @as(c_int, @intCast(index)))),
        };
    }

    pub fn setEmbedderData(self: Self, index: u32, value: Data) void {
        v8__Context__SetEmbedderData(self, @as(c_int, @intCast(index)), value);
    }
};

pub const Address = ?*opaque {};

pub const Data = extern struct {
    handle: if (binding.opts.is_direct_handle) Address else *Address,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .handle = @ptrCast(o.?),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .handle = @ptrCast(o orelse return null) };
    }
};

pub const Value = extern struct {
    extern fn v8__Value__ToString(self: Value, context: Context) ?*Address;

    data: Data,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .data = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .data = Data.from_opaque_maybe(o) orelse return null };
    }

    pub fn toString(self: @This(), context: Context) !String {
        return String.from_opaque_maybe(v8__Value__ToString(self, context)) orelse return error.JsException;
    }
};

pub const Object = extern struct {
    extern fn v8__Object__New(isolate: *Isolate.Opaque) ?*Address;
    extern fn v8__Object__New__with_prototype_and_properties(
        isolate: *Isolate.Opaque,
        prototype_or_null: ?Value,
        names: [*]const Name,
        values: [*]const Value,
        length: usize,
    ) ?*Address;
    extern fn v8__Object__Get(self: Object, context: Context, key: Value) ?*Address;
    extern fn v8__Object__GetWithReceiver(self: Object, context: Context, key: Value, receiver: Object) ?*Address;
    extern fn v8__Object__GetIndex(self: Object, context: Context, index: u32) ?*Address;
    extern fn v8__Object__GetAlignedPointerFromInternalField(self: Object, index: c_int) ?*anyopaque;
    extern fn v8__Object__SetAlignedPointerInInternalField(self: Object, index: c_int, value: ?*anyopaque) void;
    extern fn v8__Object__IsApiWrapper(self: Object) bool;
    extern fn v8__Object__GetPrototype(self: Object) ?*Address;
    extern fn v8__Object__Set(self: Object, context: Context, key: Value, value: Value) support.MaybeBool;
    extern fn v8__Object__SetWithReceiver(self: Object, context: Context, key: Value, value: Value, receiver: Object) support.MaybeBool;
    extern fn v8__Object__SetIndex(self: Object, context: Context, index: u32, value: Value) support.MaybeBool;
    extern fn v8__Object__SetPrototype(self: Object, context: Context, prototype: Value) support.MaybeBool;
    extern fn v8__Object__GetConstructorName(self: Object) ?*Address;
    extern fn v8__Object__CreateDataProperty(self: Object, context: Context, key: Name, value: Value) support.MaybeBool;
    extern fn v8__Object__DefineOwnProperty(self: Object, context: Context, key: Name, value: Value, attr: PropertyAttribute) support.MaybeBool;
    extern fn v8__Object__DefineProperty(self: Object, context: Context, key: Name, desc: *PropertyDescriptor.Opaque) support.MaybeBool;
    extern fn v8__Object__SetAccessor(
        self: Object,
        context: Context,
        key: Name,
        getter: AccessorNameGetterCallback,
        setter: ?AccessorNameSetterCallback,
        data_or_null: ?*const Value,
        attr: PropertyAttribute,
    ) support.MaybeBool;
    extern fn v8__Object__GetIdentityHash(self: Object) c_int;
    extern fn v8__Object__GetCreationContext(self: Object) ?*Address;

    value: Value,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .value = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .value = Value.from_opaque_maybe(o) orelse return null };
    }

    pub fn init(isolate: Isolate) Object {
        return from_opaque(v8__Object__New(isolate.handle));
    }

    pub fn initWithProperties(
        isolate: Isolate,
        prototype: ?Value,
        names: []const Name,
        values: []const Value,
    ) Object {
        std.debug.assert(names.len == values.len);
        return from_opaque(v8__Object__New__with_prototype_and_properties(
            isolate.handle,
            prototype,
            names.ptr,
            values.ptr,
            names.len,
        ));
    }

    pub fn get(self: Object, context: Context, key: Value) ?Value {
        return Value.from_opaque_maybe(v8__Object__Get(self, context, key));
    }

    pub fn getWithReceiver(self: Object, context: Context, key: Value, receiver: Object) ?Value {
        return Value.from_opaque_maybe(v8__Object__GetWithReceiver(self, context, key, receiver));
    }

    pub fn getIndex(self: Object, context: Context, index: u32) ?Value {
        return Value.from_opaque_maybe(v8__Object__GetIndex(self, context, index));
    }

    pub fn getAlignedPointerFromInternalField(self: Object, index: u32) ?*anyopaque {
        return v8__Object__GetAlignedPointerFromInternalField(self, @as(c_int, @intCast(index)));
    }

    pub fn setAlignedPointerInInternalField(self: Object, index: u32, value: ?*anyopaque) void {
        v8__Object__SetAlignedPointerInInternalField(self, @as(c_int, @intCast(index)), value);
    }

    pub fn isApiWrapper(self: Object) bool {
        return v8__Object__IsApiWrapper(self);
    }

    pub fn getPrototype(self: Object) ?Value {
        return Value.from_opaque_maybe(v8__Object__GetPrototype(self));
    }

    pub fn set(self: Object, context: Context, key: Value, value: Value) ?bool {
        return v8__Object__Set(self, context, key, value).as_maybe_bool();
    }

    pub fn setWithReceiver(self: Object, context: Context, key: Value, value: Value, receiver: Object) ?bool {
        return v8__Object__SetWithReceiver(self, context, key, value, receiver).as_maybe_bool();
    }

    pub fn setIndex(self: Object, context: Context, index: u32, value: Value) ?bool {
        return v8__Object__SetIndex(self, context, index, value).as_maybe_bool();
    }

    pub fn setPrototype(self: Object, context: Context, prototype: Value) ?bool {
        return v8__Object__SetPrototype(self, context, prototype).as_maybe_bool();
    }

    pub fn getConstructorName(self: Object) String {
        return String.from_opaque(v8__Object__GetConstructorName(self));
    }

    pub fn createDataProperty(self: Object, context: Context, key: Name, value: Value) ?bool {
        return v8__Object__CreateDataProperty(self, context, key, value).as_maybe_bool();
    }

    pub fn defineOwnProperty(self: Object, context: Context, key: Name, value: Value, attr: PropertyAttribute) ?bool {
        return v8__Object__DefineOwnProperty(self, context, key, value, attr).as_maybe_bool();
    }

    pub fn defineProperty(self: Object, context: Context, key: Name, desc: *PropertyDescriptor) ?bool {
        return v8__Object__DefineProperty(self, context, key, &desc.inner).as_maybe_bool();
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
        return v8__Object__SetAccessor(
            self,
            context,
            key,
            getter,
            setter,
            if (data) |*v| v else null,
            attr,
        ).as_maybe_bool();
    }

    pub fn getIdentityHash(self: Object) i32 {
        return @as(i32, @intCast(v8__Object__GetIdentityHash(self)));
    }

    pub fn getCreationContext(self: Object) ?Context {
        return Context.from_opaque_maybe(v8__Object__GetCreationContext(self));
    }
};

pub const Primitive = extern struct {
    value: Value,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .value = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .value = Value.from_opaque_maybe(o) orelse return null };
    }
};

pub const Numeric = extern struct {
    primitive: Primitive,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .primitive = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .primitive = Primitive.from_opaque_maybe(o) orelse return null };
    }
};

pub const Number = extern struct {
    extern fn v8__Number__New(isolate: *Isolate.Opaque, value: f64) ?*Address;
    extern fn v8__Number__NewInt(isolate: *Isolate.Opaque, value: i32) ?*Address;
    extern fn v8__Number__NewUInt(isolate: *Isolate.Opaque, value: u32) ?*Address;
    extern fn v8__Number__Value(self: Number) f64;

    numeric: Numeric,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .numeric = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .numeric = .from_opaque_maybe(o) orelse return null };
    }

    pub fn init(isolate: Isolate, value: f64) @This() {
        return .from_opaque(v8__Number__New(isolate.handle, value));
    }

    pub fn initInt(isolate: Isolate, value: i32) @This() {
        return .from_opaque(v8__Number__NewInt(isolate.handle, value));
    }

    pub fn initUInt(isolate: Isolate, value: u32) @This() {
        return .from_opaque(v8__Number__NewUInt(isolate.handle, value));
    }

    pub fn Value(self: @This()) f64 {
        return v8__Number__Value(self);
    }
};

pub const Name = extern struct {
    primitive: Primitive,

    pub fn from_opaque(o: ?*Address) @This() {
        return .{
            .primitive = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .primitive = Primitive.from_opaque_maybe(o) orelse return null };
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

    extern fn v8__String__NewFromUtf8(isolate: *Isolate.Opaque, data: [*]const u8, new_type: NewStringType, length: c_int) ?*Address;
    extern fn v8__String__NewFromOneByte(isolate: *Isolate.Opaque, data: [*]const u8, new_type: NewStringType, length: c_int) ?*Address;
    extern fn v8__String__NewFromTwoByte(isolate: *Isolate.Opaque, data: [*]const u16, new_type: NewStringType, length: c_int) ?*Address;
    extern fn v8__String__Length(self: String) c_int;
    extern fn v8__String__Utf8Length(self: String, isolate: *Isolate.Opaque) c_int;
    extern fn v8__String__WriteUtf8(self: String, isolate: *Isolate.Opaque, buffer: [*]u8, capacity: usize, flags: c_int, processed_characters_return: ?*usize) usize;
    extern fn v8__String__NewExternalOneByteStatic(isolate: *Isolate.Opaque, data: [*]const u8, length: c_int) ?*Address;
    extern fn v8__String__NewExternalTwoByteStatic(isolate: *Isolate.Opaque, data: [*]const u16, length: c_int) ?*Address;

    name: Name,

    const Self = @This();

    pub fn from_opaque(o: *anyopaque) Self {
        return .{
            .name = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?@This() {
        return .{ .name = Name.from_opaque_maybe(o) orelse return null };
    }

    pub fn initUtf8(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = .from_opaque(v8__String__NewFromUtf8(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))),
        };
    }

    pub fn initOneByte(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = .from_opaque(v8__String__NewFromOneByte(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))),
        };
    }

    pub fn initTwoByte(isolate: Isolate, str: []const u16) Self {
        return .{
            .name = .from_opaque(v8__String__NewFromTwoByte(isolate.handle, str.ptr, .Normal, @as(c_int, @intCast(str.len)))),
        };
    }

    pub fn initOneByteStatic(isolate: Isolate, str: []const u8) Self {
        return .{
            .name = .from_opaque(v8__String__NewExternalOneByteStatic(isolate.handle, str.ptr, @as(c_int, @intCast(str.len)))),
        };
    }

    pub fn initTwoByteStatic(isolate: Isolate, str: []const u16) Self {
        return .{
            .name = .from_opaque(v8__String__NewExternalTwoByteStatic(isolate.handle, str.ptr, @as(c_int, @intCast(str.len)))),
        };
    }

    pub fn len(self: Self) usize {
        return @as(usize, @intCast(v8__String__Length(self.handle)));
    }

    pub fn lenUtf8(self: Self, isolate: Isolate) usize {
        return @as(usize, @intCast(v8__String__Utf8Length(self, isolate.handle)));
    }

    pub fn writeUtf8(self: Self, isolate: Isolate, buf: []u8) usize {
        const flags = WriteFlags.ReplaceInvalidUtf8;
        return v8__String__WriteUtf8(self, isolate.handle, buf.ptr, buf.len, flags, null);
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
        extern fn v8__ArrayBuffer__Allocator__NewDefaultAllocator() ?*Opaque;
        extern fn v8__ArrayBuffer__Allocator__DELETE(handle: *Opaque) void;

        pub fn initDefault() @This() {
            return .{
                .handle = v8__ArrayBuffer__Allocator__NewDefaultAllocator().?,
            };
        }

        pub fn deinit(self: @This()) void {
            v8__ArrayBuffer__Allocator__DELETE(self.handle);
        }
    };
};

pub const Script = extern struct {
    extern fn v8__Script__Compile(context: Context, source: String, origin: ?*const ScriptOrigin.Opaque) ?*Address;
    extern fn v8__Script__Run(self: Script, context: Context) ?*Address;

    data: Data,

    const Self = @This();

    pub fn from_opaque(o: ?*Address) Self {
        return .{
            .data = .from_opaque(o),
        };
    }

    pub fn from_opaque_maybe(o: ?*Address) ?Self {
        return .{
            .data = Data.from_opaque_maybe(o) orelse return null,
        };
    }

    pub fn compile(context: Context, source: String, origin: ?ScriptOrigin) !Self {
        const ptr = if (origin) |o| &o.inner else null;
        return @This().from_opaque_maybe(v8__Script__Compile(context, source, ptr)) orelse return error.JsException;
    }

    pub fn run(self: Self, context: Context) !Value {
        return Value.from_opaque_maybe(v8__Script__Run(self, context)) orelse return error.JsException;
    }
};

pub const TryCatch = struct {
    pub const Opaque = [binding.sizes.TryCatch]u8;

    extern fn v8__TryCatch__CONSTRUCT(ptr: *Opaque, isolate: *Isolate.Opaque) void;
    extern fn v8__TryCatch__DESTRUCT(ptr: *Opaque) void;
    extern fn v8__TryCatch__HasCaught(self: *const Opaque) bool;
    extern fn v8__TryCatch__CanContinue(self: *const Opaque) bool;
    extern fn v8__TryCatch__HasTerminated(self: *const Opaque) bool;
    extern fn v8__TryCatch__Exception(self: *const Opaque) ?*Address;
    extern fn v8__TryCatch__StackTrace(self: *const Opaque, context: Context) ?*Address;
    extern fn v8__TryCatch__Message(self: *const Opaque) ?*Message.Opaque;
    extern fn v8__TryCatch__Reset(self: *Opaque) void;
    extern fn v8__TryCatch__ReThrow(self: *Opaque) ?*Address;
    extern fn v8__TryCatch__IsVerbose(self: *const Opaque) bool;
    extern fn v8__TryCatch__SetVerbose(self: *Opaque, value: bool) void;
    extern fn v8__TryCatch__SetCaptureMessage(self: *Opaque, value: bool) void;

    inner: Opaque,

    const Self = @This();

    pub fn init(self: *Self, isolate: Isolate) void {
        v8__TryCatch__CONSTRUCT(&self.inner, isolate.handle);
    }

    pub fn deinit(self: *Self) void {
        v8__TryCatch__DESTRUCT(&self.inner);
    }

    pub fn hasCaught(self: *const Self) bool {
        return v8__TryCatch__HasCaught(&self.inner);
    }

    pub fn canContinue(self: *const Self) bool {
        return v8__TryCatch__CanContinue(&self.inner);
    }

    pub fn hasTerminated(self: *const Self) bool {
        return v8__TryCatch__HasTerminated(&self.inner);
    }

    pub fn getException(self: *const Self) ?Value {
        const handle = v8__TryCatch__Exception(&self.inner) orelse return null;
        return .from_opaque_maybe(handle);
    }

    pub fn getStackTrace(self: *const Self, context: Context) ?Value {
        const handle = v8__TryCatch__StackTrace(&self.inner, context) orelse return null;
        return .from_opaque_maybe(handle);
    }

    pub fn getMessage(self: *const Self) ?Message {
        const handle = v8__TryCatch__Message(&self.inner) orelse return null;
        return .{ .handle = handle };
    }

    pub fn reset(self: *Self) void {
        v8__TryCatch__Reset(&self.inner);
    }

    pub fn reThrow(self: *Self) ?Value {
        const handle = v8__TryCatch__ReThrow(&self.inner) orelse return null;
        return .{ .handle = handle };
    }

    pub fn isVerbose(self: *const Self) bool {
        return v8__TryCatch__IsVerbose(&self.inner);
    }

    pub fn setVerbose(self: *Self, value: bool) void {
        v8__TryCatch__SetVerbose(&self.inner, value);
    }

    pub fn setCaptureMessage(self: *Self, value: bool) void {
        v8__TryCatch__SetCaptureMessage(&self.inner, value);
    }
};

pub const StackFrame = struct {
    pub const Opaque = opaque {};

    extern fn v8__StackFrame__GetLineNumber(self: *const Opaque) c_int;
    extern fn v8__StackFrame__GetColumn(self: *const Opaque) c_int;
    extern fn v8__StackFrame__GetScriptId(self: *const Opaque) c_int;
    extern fn v8__StackFrame__GetScriptName(self: *const Opaque) ?*String.Opaque;
    extern fn v8__StackFrame__GetScriptNameOrSourceURL(self: *const Opaque) ?*String.Opaque;
    extern fn v8__StackFrame__GetFunctionName(self: *const Opaque) ?*String.Opaque;
    extern fn v8__StackFrame__IsEval(self: *const Opaque) bool;
    extern fn v8__StackFrame__IsConstructor(self: *const Opaque) bool;
    extern fn v8__StackFrame__IsWasm(self: *const Opaque) bool;
    extern fn v8__StackFrame__IsUserJavaScript(self: *const Opaque) bool;

    handle: *Opaque,

    const Self = @This();

    pub fn getLineNumber(self: Self) u32 {
        return @as(u32, @intCast(v8__StackFrame__GetLineNumber(self.handle)));
    }

    pub fn getColumn(self: Self) u32 {
        return @as(u32, @intCast(v8__StackFrame__GetColumn(self.handle)));
    }

    pub fn getScriptId(self: Self) u32 {
        return @as(u32, @intCast(v8__StackFrame__GetScriptId(self.handle)));
    }

    pub fn getScriptName(self: Self) ?String {
        if (v8__StackFrame__GetScriptName(self.handle)) |ptr| {
            return .{ .handle = ptr };
        }
        return null;
    }

    pub fn getScriptNameOrSourceUrl(self: Self) ?String {
        if (v8__StackFrame__GetScriptNameOrSourceURL(self.handle)) |ptr| {
            return .{ .handle = ptr };
        }
        return null;
    }

    pub fn getFunctionName(self: Self) ?String {
        if (v8__StackFrame__GetFunctionName(self.handle)) |ptr| {
            return .{ .handle = ptr };
        }
        return null;
    }

    pub fn isEval(self: Self) bool {
        return v8__StackFrame__IsEval(self.handle);
    }

    pub fn isConstructor(self: Self) bool {
        return v8__StackFrame__IsConstructor(self.handle);
    }

    pub fn isWasm(self: Self) bool {
        return v8__StackFrame__IsWasm(self.handle);
    }

    pub fn isUserJavascript(self: Self) bool {
        return v8__StackFrame__IsUserJavaScript(self.handle);
    }
};

pub const StackTrace = struct {
    pub const Opaque = opaque {};

    extern fn v8__StackTrace__GetFrameCount(self: *const Opaque) c_int;
    extern fn v8__StackTrace__GetFrame(self: *const Opaque, isolate: *Isolate.Opaque, index: u32) ?*StackFrame.Opaque;
    extern fn v8__StackTrace__CurrentStackTrace(isolate: *Isolate.Opaque, frame_limit: c_int) ?*Opaque;
    extern fn v8__StackTrace__CurrentScriptNameOrSourceURL(isolate: *Isolate.Opaque) ?*String.Opaque;

    handle: *Opaque,

    const Self = @This();

    pub fn getFrameCount(self: Self) u32 {
        return @as(u32, @intCast(v8__StackTrace__GetFrameCount(self.handle)));
    }

    pub fn getFrame(self: Self, isolate: Isolate, index: u32) StackFrame {
        return .{
            .handle = v8__StackTrace__GetFrame(self.handle, isolate.handle, index).?,
        };
    }

    pub fn getCurrentStackTrace(isolate: Isolate, frame_limit: u32) StackTrace {
        return .{
            .handle = v8__StackTrace__CurrentStackTrace(isolate.handle, @as(c_int, @intCast(frame_limit))).?,
        };
    }

    pub fn getCurrentScriptNameOrSourceUrl(isolate: Isolate) ?String {
        if (v8__StackTrace__CurrentScriptNameOrSourceURL(isolate.handle)) |ptr| {
            return .{ .handle = ptr };
        }
        return null;
    }
};

pub const Message = struct {
    pub const Opaque = opaque {};

    extern fn v8__Message__Get(self: *const Opaque) ?*String.Opaque;
    extern fn v8__Message__GetSourceLine(self: *const Opaque, context: Context) ?*Address;
    extern fn v8__Message__GetScriptResourceName(self: *const Opaque) ?*Value.Opaque;
    extern fn v8__Message__GetLineNumber(self: *const Opaque, context: Context) c_int;
    extern fn v8__Message__GetStackTrace(self: *const Opaque) ?*StackTrace.Opaque;
    extern fn v8__Message__GetStartPosition(self: *const Opaque) c_int;
    extern fn v8__Message__GetEndPosition(self: *const Opaque) c_int;
    extern fn v8__Message__GetStartColumn(self: *const Opaque) c_int;
    extern fn v8__Message__GetEndColumn(self: *const Opaque) c_int;
    extern fn v8__Message__IsSharedCrossOrigin(self: *const Opaque) bool;
    extern fn v8__Message__GetWasmFunctionIndex(self: *const Opaque) c_int;
    extern fn v8__Message__ErrorLevel(self: *const Opaque) c_int;

    handle: *Opaque,

    const Self = @This();

    pub fn get(self: Self) String {
        return .{ .handle = v8__Message__Get(self.handle).? };
    }

    pub fn getSourceLine(self: Self, context: Context) ?String {
        const ptr = v8__Message__GetSourceLine(self.handle, context);
        return .from_opaque_maybe(ptr);
    }

    pub fn getScriptResourceName(self: Self) Value {
        return .{ .handle = v8__Message__GetScriptResourceName(self.handle).? };
    }

    pub fn getLineNumber(self: Self, context: Context) ?u32 {
        const res = v8__Message__GetLineNumber(self.handle, context.handle);
        if (res != -1) return @as(u32, @intCast(res));
        return null;
    }

    pub fn getStartColumn(self: Self) ?u32 {
        const res = v8__Message__GetStartColumn(self.handle);
        if (res != -1) return @as(u32, @intCast(res));
        return null;
    }

    pub fn getEndColumn(self: Self) ?u32 {
        const res = v8__Message__GetEndColumn(self.handle);
        if (res != -1) return @as(u32, @intCast(res));
        return null;
    }

    pub fn getStackTrace(self: Self) ?StackTrace {
        if (v8__Message__GetStackTrace(self.handle)) |ptr| {
            return .{ .handle = ptr };
        }
        return null;
    }

    pub fn getStartPosition(self: Self) i32 {
        return v8__Message__GetStartPosition(self.handle);
    }

    pub fn getEndPosition(self: Self) i32 {
        return v8__Message__GetEndPosition(self.handle);
    }

    pub fn getWasmFunctionIndex(self: Self) i32 {
        return v8__Message__GetWasmFunctionIndex(self.handle);
    }

    pub fn getErrorLevel(self: Self) i32 {
        return v8__Message__ErrorLevel(self.handle);
    }

    pub fn isSharedCrossOrigin(self: Self) bool {
        return v8__Message__IsSharedCrossOrigin(self.handle);
    }
};

pub const ScriptOrigin = struct {
    pub const Opaque = [binding.sizes.ScriptOrigin]u8;

    const Self = @This();

    extern fn v8__ScriptOrigin__CONSTRUCT(
        ptr: *Opaque,
        resource_name: Value,
        resource_line_offset: c_int,
        resource_column_offset: c_int,
        resource_is_shared_cross_origin: bool,
        script_id: c_int,
        source_map_url: ?*Address,
        resource_is_opaque: bool,
        is_wasm: bool,
        is_module: bool,
        host_defined_options: ?*Address,
    ) void;

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
        resource_line_offset: i32,
        resource_column_offset: i32,
        resource_is_shared_cross_origin: bool,
        script_id: i32,
        source_map_url: ?Value,
        resource_is_opaque: bool,
        is_wasm: bool,
        is_module: bool,
        host_defined_options: ?Data,
    ) Self {
        var res: ScriptOrigin = undefined;
        v8__ScriptOrigin__CONSTRUCT(
            &res.inner,
            resource_name,
            @as(c_int, @intCast(resource_line_offset)),
            @as(c_int, @intCast(resource_column_offset)),
            resource_is_shared_cross_origin,
            @as(c_int, @intCast(script_id)),
            if (source_map_url) |v| v.data.handle else null,
            resource_is_opaque,
            is_wasm,
            is_module,
            if (host_defined_options) |v| v.handle else null,
        );
        return res;
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
