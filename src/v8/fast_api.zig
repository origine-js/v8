const v8 = @import("../v8.zig");
const Number = v8.Number;

pub const CTypeInfo = extern struct {
    /// Matches `v8::CTypeInfo::Type`, which counts from zero.
    type: enum(u8) {
        Void = 0,
        Bool = 1,
        Uint8 = 2,
        Int32 = 3,
        Uint32 = 4,
        Int64 = 5,
        Uint64 = 6,
        Float32 = 7,
        Float64 = 8,
        Pointer = 9,
        V8Value = 10,
        SeqOneByteString = 11,
        ApiObject = 12,
        Any = 13,
        /// Marks the trailing `FastApiCallbackOptions` parameter (`kCallbackOptionsType`).
        CallbackOptions = 255,
    },
    /// `v8::CTypeInfo::Flags` is a `uint8_t` enum: sizeof(CTypeInfo) == 2.
    flags: packed struct(u8) {
        AllowSharedBit: bool = false,
        EnforceRangeBit: bool = false,
        ClampBit: bool = false,
        IsRestrictedBit: bool = false,
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

/// Passed by reference as the last argument of a fast callback whose `CFunctionInfo` ends in
/// `CTypeInfo.Type.CallbackOptions`. Owned by V8 and valid only until the fast call returns.
pub const FastApiCallbackOptions = extern struct {
    isolate: ?*anyopaque,
    /// Raw `Local<Value>` bits of the `data` given to the `FunctionTemplate`; decode with
    /// `v8.fromRawLocal`. Valid only until the fast call returns.
    data: usize,
};
