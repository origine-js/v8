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
