//! Zig wrappers for V8. Each type lives in `v8/<Type>.zig`; this file re-exports them.

/// Build capability measured from the engine headers, never inferred from JS globals.
pub const has_webassembly = @import("generated/binding.zig").opts.has_webassembly;
/// Wasm-only exports are absent from this namespace when the engine omits Wasm.
pub const wasm = if (has_webassembly) @import("v8/wasm.zig") else struct {};
pub const StackTraceLimit = @import("v8/StackTraceLimit.zig").StackTraceLimit;
pub const localNew = @import("v8/handle.zig").localNew;
pub const Callbacks = @import("v8/callbacks.zig").Callbacks;
pub const HeapSpaceStatistics = @import("v8/native_types.zig").HeapSpaceStatistics;
pub const ZigAllocatorTable = @import("v8/native_types.zig").ZigAllocatorTable;
pub const StalledTopLevelAwaitMessage = @import("v8/native_types.zig").StalledTopLevelAwaitMessage;
pub const SharedBackingStore = @import("v8/native_types.zig").SharedBackingStore;
// Exact C++ name prevents the extern resolver from treating shared_ptr as a local handle.
pub const std_shared_ptr_BackingStore = SharedBackingStore;
pub const support = @import("v8/support.zig");
pub const simdutf = @import("v8/simdutf.zig");
pub const Platform = @import("v8/Platform.zig").Platform;
pub const V8 = @import("v8/V8.zig").V8;
pub const ResourceConstraints = @import("v8/ResourceConstraints.zig").ResourceConstraints;
pub const FixedArray = @import("v8/FixedArray.zig").FixedArray;
pub const PrimitiveArray = @import("v8/PrimitiveArray.zig").PrimitiveArray;
pub const Array = @import("v8/Array.zig").Array;
pub const ModuleImportPhase = @import("v8/enums.zig").ModuleImportPhase;
pub const PropertyAttribute = @import("v8/enums.zig").PropertyAttribute;
pub const ConstructorBehavior = @import("v8/enums.zig").ConstructorBehavior;
pub const SideEffectType = @import("v8/enums.zig").SideEffectType;
pub const MicrotasksPolicy = @import("v8/enums.zig").MicrotasksPolicy;
pub const HostInitializeImportMetaObjectCallback = @import("v8/callbacks.zig").HostInitializeImportMetaObjectCallback;
pub const HostImportModuleDynamicallyCallback = @import("v8/callbacks.zig").HostImportModuleDynamicallyCallback;
pub const HostImportModuleWithPhaseDynamicallyCallback = @import("v8/callbacks.zig").HostImportModuleWithPhaseDynamicallyCallback;
pub const AccessorNameGetterCallback = @import("v8/callbacks.zig").AccessorNameGetterCallback;
pub const AccessorNameSetterCallback = @import("v8/callbacks.zig").AccessorNameSetterCallback;
pub const FunctionCallback = @import("v8/callbacks.zig").FunctionCallback;
pub const Isolate = @import("v8/Isolate.zig").Isolate;
pub const HandleScope = @import("v8/HandleScope.zig").HandleScope;
pub const CTypeInfo = @import("v8/fast_api.zig").CTypeInfo;
pub const CFunctionInfo = @import("v8/fast_api.zig").CFunctionInfo;
pub const CFunction = @import("v8/fast_api.zig").CFunction;
pub const FastApiCallbackOptions = @import("v8/fast_api.zig").FastApiCallbackOptions;
pub const ReturnValue = @import("v8/ReturnValue.zig").ReturnValue;
pub const PropertyCallbackInfo = @import("v8/PropertyCallbackInfo.zig").PropertyCallbackInfo;
pub const PropertyDescriptor = @import("v8/PropertyDescriptor.zig").PropertyDescriptor;
pub const Template = @import("v8/Template.zig").Template;
pub const FunctionCallbackInfo = @import("v8/FunctionCallbackInfo.zig").FunctionCallbackInfo;
pub const Signature = @import("v8/Signature.zig").Signature;
pub const Function = @import("v8/Function.zig").Function;
pub const Intrinsics = @import("v8/Intrinsics.zig").Intrinsics;
pub const FunctionTemplate = @import("v8/FunctionTemplate.zig").FunctionTemplate;
pub const ObjectTemplate = @import("v8/ObjectTemplate.zig").ObjectTemplate;
pub const MicrotaskQueue = @import("v8/MicrotaskQueue.zig").MicrotaskQueue;
pub const MicrotaskQueueHandle = @import("v8/MicrotaskQueue.zig").MicrotaskQueueHandle;
pub const Context = @import("v8/Context.zig").Context;
pub const Address = @import("v8/handle.zig").Address;
pub const Handle = @import("v8/handle.zig").Handle;
pub const MaybeHandle = @import("v8/handle.zig").MaybeHandle;
pub const raw_empty_local = @import("v8/handle.zig").raw_empty_local;
pub const toRawLocal = @import("v8/handle.zig").toRawLocal;
pub const fromRawLocal = @import("v8/handle.zig").fromRawLocal;
pub const Global = @import("v8/Global.zig").Global;
pub const Weak = @import("v8/Weak.zig").Weak;
pub const Data = @import("v8/Data.zig").Data;
pub const Value = @import("v8/Value.zig").Value;
pub const Object = @import("v8/Object.zig").Object;
pub const External = @import("v8/External.zig").External;
pub const Primitive = @import("v8/Primitive.zig").Primitive;
pub const Promise = @import("v8/Promise.zig").Promise;
pub const Numeric = @import("v8/Numeric.zig").Numeric;
pub const Number = @import("v8/Number.zig").Number;
pub const Name = @import("v8/Name.zig").Name;
pub const String = @import("v8/String.zig").String;
pub const Module = @import("v8/Module.zig").Module;
pub const ArrayBuffer = @import("v8/ArrayBuffer.zig").ArrayBuffer;
pub const Script = @import("v8/Script.zig").Script;
pub const TryCatch = @import("v8/TryCatch.zig").TryCatch;
pub const StackFrame = @import("v8/StackFrame.zig").StackFrame;
pub const StackTrace = @import("v8/StackTrace.zig").StackTrace;
pub const Message = @import("v8/Message.zig").Message;
pub const ScriptOrigin = @import("v8/ScriptOrigin.zig").ScriptOrigin;
pub const HeapStatistics = @import("v8/HeapStatistics.zig").HeapStatistics;
pub const BigInt = @import("v8/BigInt.zig").BigInt;
pub const Boolean = @import("v8/Boolean.zig").Boolean;
pub const Integer = @import("v8/Integer.zig").Integer;
pub const Int32 = @import("v8/Int32.zig").Int32;
pub const Uint32 = @import("v8/Uint32.zig").Uint32;
pub const Map = @import("v8/Map.zig").Map;
pub const Set = @import("v8/Set.zig").Set;
pub const Symbol = @import("v8/Symbol.zig").Symbol;
pub const Private = @import("v8/Private.zig").Private;
pub const Proxy = @import("v8/Proxy.zig").Proxy;
pub const RegExp = @import("v8/RegExp.zig").RegExp;
pub const JSON = @import("v8/JSON.zig").JSON;
pub const Exception = @import("v8/Exception.zig").Exception;
pub const ArrayBufferView = @import("v8/ArrayBufferView.zig").ArrayBufferView;
pub const TypedArray = @import("v8/TypedArray.zig").TypedArray;
pub const DataView = @import("v8/DataView.zig").DataView;
pub const SharedArrayBuffer = @import("v8/SharedArrayBuffer.zig").SharedArrayBuffer;
pub const BackingStore = @import("v8/BackingStore.zig").BackingStore;
pub const Int8Array = @import("v8/typed_arrays.zig").Int8Array;
pub const Uint8Array = @import("v8/typed_arrays.zig").Uint8Array;
pub const Uint8ClampedArray = @import("v8/typed_arrays.zig").Uint8ClampedArray;
pub const Int16Array = @import("v8/typed_arrays.zig").Int16Array;
pub const Uint16Array = @import("v8/typed_arrays.zig").Uint16Array;
pub const Int32Array = @import("v8/typed_arrays.zig").Int32Array;
pub const Uint32Array = @import("v8/typed_arrays.zig").Uint32Array;
pub const Float16Array = @import("v8/typed_arrays.zig").Float16Array;
pub const Float32Array = @import("v8/typed_arrays.zig").Float32Array;
pub const Float64Array = @import("v8/typed_arrays.zig").Float64Array;
pub const BigInt64Array = @import("v8/typed_arrays.zig").BigInt64Array;
pub const BigUint64Array = @import("v8/typed_arrays.zig").BigUint64Array;
pub const ModuleRequest = @import("v8/ModuleRequest.zig").ModuleRequest;
pub const UnboundScript = @import("v8/UnboundScript.zig").UnboundScript;
pub const UnboundModuleScript = @import("v8/UnboundModuleScript.zig").UnboundModuleScript;
pub const ScriptOrModule = @import("v8/ScriptOrModule.zig").ScriptOrModule;
pub const ScriptCompiler = @import("v8/ScriptCompiler.zig").ScriptCompiler;
pub const SnapshotCreator = @import("v8/SnapshotCreator.zig").SnapshotCreator;
pub const StartupData = @import("v8/StartupData.zig").StartupData;
pub const Location = @import("v8/Location.zig").Location;
pub const PromiseRejectMessage = @import("v8/PromiseRejectMessage.zig").PromiseRejectMessage;
pub const Eternal = @import("v8/Eternal.zig").Eternal;
pub const TracedReference = @import("v8/TracedReference.zig").TracedReference;
pub const HeapProfiler = @import("v8/HeapProfiler.zig").HeapProfiler;
pub const ExternalOneByteStringResource = @import("v8/ExternalOneByteStringResource.zig").ExternalOneByteStringResource;
pub const WeakCallbackInfo = @import("v8/WeakCallbackInfo.zig").WeakCallbackInfo;

const std = @import("std");
const e = @import("generated/externs.gen.zig");

// Zig only analyzes what is used, so reference every declaration explicitly:
// this is what proves the wrappers still match the generated externs.
/// Zig only analyzes what is used, so reference every declaration of `T` and of
/// the types nested in it (depth-limited: wrappers alias themselves via `Self`).
/// Accepts compile-time values; retains no runtime resources.
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

test "wrappers type-check against the generated externs" {
    std.testing.refAllDecls(e);
    refAllNested(@This(), 3);
}

test "Layouts: extern structs match the C++ sizes" {
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.HandleScope), @sizeOf(@This().HandleScope));
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.TryCatch), @sizeOf(@This().TryCatch));
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.ScriptOrigin), @sizeOf(@This().ScriptOrigin));
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.PropertyDescriptor), @sizeOf(@This().PropertyDescriptor));
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.Isolate_CreateParams), @sizeOf(@This().Isolate.CreateParams));
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.ResourceConstraints), @sizeOf(@This().ResourceConstraints));
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.HeapStatistics), @sizeOf(@This().HeapStatistics));
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.CFunction), @sizeOf(@This().CFunction));
    try std.testing.expectEqual(@as(usize, @import("generated/binding.zig").sizes.CTypeInfo), @sizeOf(@This().CTypeInfo));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(@This().PropertyAttribute));
}
