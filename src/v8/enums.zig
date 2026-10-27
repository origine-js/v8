const v8 = @import("../v8.zig");

pub const ModuleImportPhase = enum(c_int) {
    Source,
    Defer,
    Evaluation,
};

pub const PropertyAttribute = packed struct(u32) {
    ReadOnly: bool = false,
    DontEnum: bool = false,
    DontDelete: bool = false,
    _unused: u29 = 0,
};

/// Mirrors `v8::PropertyFilter` (bit flags; all clear is `ALL_PROPERTIES`).
pub const PropertyFilter = packed struct(u32) {
    OnlyWritable: bool = false,
    OnlyEnumerable: bool = false,
    OnlyConfigurable: bool = false,
    SkipStrings: bool = false,
    SkipSymbols: bool = false,
    _unused: u27 = 0,
};

/// Mirrors `v8::KeyCollectionMode`.
pub const KeyCollectionMode = enum(c_int) { OwnOnly, IncludePrototypes };

/// Mirrors `v8::IndexFilter`.
pub const IndexFilter = enum(c_int) { IncludeIndices, SkipIndices };

/// Mirrors `v8::KeyConversionMode`.
pub const KeyConversionMode = enum(c_int) { ConvertToString, KeepNumbers, NoNumbers };

/// Mirrors `v8::IntegrityLevel`.
pub const IntegrityLevel = enum(c_int) { Frozen, Sealed };

/// Mirrors `v8::MemoryPressureLevel`.
pub const MemoryPressureLevel = enum(c_int) { None, Moderate, Critical };

/// Mirrors `v8::PropertyHandlerFlags` (bit flags; all clear is `kNone`).
pub const PropertyHandlerFlags = packed struct(c_int) {
    NonMasking: bool = false,
    OnlyInterceptStrings: bool = false,
    HasNoSideEffect: bool = false,
    HasDontDeleteProperty: bool = false,
    _unused: u6 = 0,
    /// Set by V8's own handler configuration constructors; leave clear.
    InternalNewCallbacksSignatures: bool = false,
    _unused_high: u21 = 0,
};

pub const ConstructorBehavior = enum(c_int) { Throw, Allow };

pub const SideEffectType = enum(c_int) {
    HasSideEffect,
    HasNoSideEffect,
    HasSideEffectToReceiver,
};

pub const MicrotasksPolicy = enum(u32) {
    Explicit = 0,
    Scoped = 1,
    Auto = 2,
};
