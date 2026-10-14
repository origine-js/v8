const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const FixedArray = v8.FixedArray;
const ModuleImportPhase = v8.ModuleImportPhase;
const PropertyCallbackInfo = v8.PropertyCallbackInfo;
const FunctionCallbackInfo = v8.FunctionCallbackInfo;
const Context = v8.Context;
const Data = v8.Data;
const Value = v8.Value;
const Object = v8.Object;
const Promise = v8.Promise;
const Name = v8.Name;
const String = v8.String;
const Module = v8.Module;

pub const HostInitializeImportMetaObjectCallback = *const fn (Context, Module, meta: Object) callconv(.c) void;

pub const HostImportModuleDynamicallyCallback = *const fn (Context, host_defined_options: Data, resource_name: Value, specifier: String, import_attributes: FixedArray) callconv(.c) v8.MaybeHandle;

pub const HostImportModuleWithPhaseDynamicallyCallback = *const fn (Context, host_defined_options: Data, resource_name: Value, specifier: String, ModuleImportPhase, import_attributes: FixedArray) callconv(.c) v8.MaybeHandle;

pub const AccessorNameGetterCallback = *const fn (Name, *const PropertyCallbackInfo) callconv(.c) void;

pub const AccessorNameSetterCallback = *const fn (Name, Value, *const PropertyCallbackInfo) callconv(.c) void;

pub const FunctionCallback = *const fn (FunctionCallbackInfo) callconv(.c) void;

/// Callback signatures are derived from the generated ABI to stay in sync with V8.
pub const Callbacks = struct {
    pub const BackingStore_DeleterCallback = @typeInfo(@TypeOf(e.v8__SharedArrayBuffer__NewBackingStore__with_data)).@"fn".param_types[2].?;
    pub const InterruptCallback = @typeInfo(@TypeOf(e.v8__Isolate__RequestInterrupt)).@"fn".param_types[1].?;
    pub const PrepareStackTraceCallback = @typeInfo(@TypeOf(e.v8__Isolate__SetPrepareStackTraceCallback)).@"fn".param_types[1].?;
    pub const PromiseHook = @typeInfo(@TypeOf(e.v8__Isolate__SetPromiseHook)).@"fn".param_types[1].?;
    pub const PromiseRejectCallback = @typeInfo(@TypeOf(e.v8__Isolate__SetPromiseRejectCallback)).@"fn".param_types[1].?;
    pub const WasmAsyncResolvePromiseCallback = @typeInfo(@TypeOf(e.v8__Isolate__SetWasmAsyncResolvePromiseCallback)).@"fn".param_types[1].?;
    pub const HostCreateShadowRealmContextCallback = @typeInfo(@TypeOf(e.v8__Isolate__SetHostCreateShadowRealmContextCallback)).@"fn".param_types[1].?;
    pub const Isolate_UseCounterCallback = @typeInfo(@TypeOf(e.v8__Isolate__SetUseCounterCallback)).@"fn".param_types[1].?;
    pub const MessageCallback = @typeInfo(@TypeOf(e.v8__Isolate__AddMessageListenerWithErrorLevel)).@"fn".param_types[1].?;
    pub const Isolate_GCCallbackWithData = @typeInfo(@TypeOf(e.v8__Isolate__RemoveGCEpilogueCallback)).@"fn".param_types[1].?;
    pub const NearHeapLimitCallback = @typeInfo(@TypeOf(e.v8__Isolate__RemoveNearHeapLimitCallback)).@"fn".param_types[1].?;
    pub const OOMErrorCallback = @typeInfo(@TypeOf(e.v8__Isolate__SetOOMErrorHandler)).@"fn".param_types[1].?;
    pub const WasmStreamingCallback = @typeInfo(@TypeOf(e.v8__Isolate__SetWasmStreamingCallback)).@"fn".param_types[1].?;
    pub const AllowWasmCodeGenerationCallback = @typeInfo(@TypeOf(e.v8__Isolate__SetAllowWasmCodeGenerationCallback)).@"fn".param_types[1].?;
    pub const Module_ResolveModuleCallback = @typeInfo(@TypeOf(e.v8__Module__InstantiateModule)).@"fn".param_types[2].?;
    pub const Module_ResolveSourceCallback = @typeInfo(@TypeOf(e.v8__Module__InstantiateModule)).@"fn".param_types[3].?;
    pub const Module_SyntheticModuleEvaluationSteps = @typeInfo(@TypeOf(e.v8__Module__CreateSyntheticModule)).@"fn".param_types[4].?;
    pub const NamedPropertyGetterCallback = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetNamedPropertyHandler)).@"fn".param_types[1].?;
    pub const NamedPropertySetterCallback = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetNamedPropertyHandler)).@"fn".param_types[2].?;
    pub const NamedPropertyQueryCallback = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetNamedPropertyHandler)).@"fn".param_types[3].?;
    pub const NamedPropertyDeleterCallback = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetNamedPropertyHandler)).@"fn".param_types[4].?;
    pub const NamedPropertyEnumeratorCallback = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetNamedPropertyHandler)).@"fn".param_types[5].?;
    pub const NamedPropertyDefinerCallback = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetNamedPropertyHandler)).@"fn".param_types[6].?;
    pub const NamedPropertyDescriptorCallback = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetNamedPropertyHandler)).@"fn".param_types[7].?;
    pub const IndexedPropertyGetterCallbackV2 = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetIndexedPropertyHandler)).@"fn".param_types[1].?;
    pub const IndexedPropertySetterCallbackV2 = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetIndexedPropertyHandler)).@"fn".param_types[2].?;
    pub const IndexedPropertyQueryCallbackV2 = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetIndexedPropertyHandler)).@"fn".param_types[3].?;
    pub const IndexedPropertyDeleterCallbackV2 = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetIndexedPropertyHandler)).@"fn".param_types[4].?;
    pub const IndexedPropertyEnumeratorCallback = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetIndexedPropertyHandler)).@"fn".param_types[5].?;
    pub const IndexedPropertyDefinerCallbackV2 = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetIndexedPropertyHandler)).@"fn".param_types[6].?;
    pub const IndexedPropertyDescriptorCallbackV2 = @typeInfo(@TypeOf(e.v8__ObjectTemplate__SetIndexedPropertyHandler)).@"fn".param_types[7].?;
    pub const ExternalOneByteString_ZigDeinit = @typeInfo(@TypeOf(e.v8__String__NewExternalOneByte)).@"fn".param_types[3].?;
};
