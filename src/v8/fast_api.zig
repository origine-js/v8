const v8 = @import("../v8.zig");
const Number = v8.Number;

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
