//! Compile-time proof that the Zig flag structs and enums carry the values V8's headers define.
//!
//! The expected numbers are not written here: `build-tools/bindgen/layout.zon` lists each V8
//! enumerator, `zig build gen` measures it with V8's own clang into `generated/binding.zig`, and
//! `binding/layout.gen.h` static-asserts it so a V8 upgrade that renumbers one stops the C++
//! build until `gen` is rerun. Once the measurement changes, this file stops the Zig build until the type
//! is brought back in line. Accepts and returns comptime values only; retains nothing.

const std = @import("std");
const v8 = @import("../v8.zig");
const consts = @import("../generated/binding.zig").consts;

/// One V8 enumerator: the Zig field (or enum tag) that must carry its value.
const Member = struct { field: []const u8, cpp: []const u8 };

fn measured(comptime group: []const u8, comptime cpp: []const u8) comptime_int {
    return @field(consts, group ++ "_" ++ cpp);
}

/// Field names of `T` that are real flags, not padding.
fn memberCount(comptime T: type) usize {
    var n: usize = 0;
    for (@typeInfo(T).@"struct".field_names) |name| {
        if (name[0] != '_') n += 1;
    }
    return n;
}

/// `T` is a packed struct of bool flags: each member sets exactly the bit V8 names, the optional
/// `none` enumerator is the all-clear value, and no flag is missing from `members`.
fn flags(comptime T: type, comptime group: []const u8, comptime none: ?[]const u8, comptime members: []const Member) void {
    const Int = @typeInfo(T).@"struct".backing_integer.?;
    if (none) |name| {
        if (@as(comptime_int, @as(Int, @bitCast(T{}))) != measured(group, name))
            @compileError(group ++ "." ++ name ++ " is not the all-clear value of " ++ @typeName(T));
    }
    if (members.len != memberCount(T))
        @compileError(@typeName(T) ++ " has flags that are not checked against V8, or checks for flags it lacks");
    for (members) |m| {
        var value: T = .{};
        @field(value, m.field) = true;
        const bits: comptime_int = @as(Int, @bitCast(value));
        if (bits != measured(group, m.cpp))
            @compileError(std.fmt.comptimePrint("{s}.{s} is {d} in Zig but V8's {s} is {d}", .{ @typeName(T), m.field, bits, m.cpp, measured(group, m.cpp) }));
    }
}

/// `T` is an enum: each tag has the value V8 gives its enumerator, and none is missing.
fn tags(comptime T: type, comptime group: []const u8, comptime members: []const Member) void {
    if (members.len != @typeInfo(T).@"enum".field_names.len)
        @compileError(@typeName(T) ++ " has tags that are not checked against V8, or checks for tags it lacks");
    for (members) |m| {
        const value: comptime_int = @intFromEnum(@field(T, m.field));
        if (value != measured(group, m.cpp))
            @compileError(std.fmt.comptimePrint("{s}.{s} is {d} in Zig but V8's {s} is {d}", .{ @typeName(T), m.field, value, m.cpp, measured(group, m.cpp) }));
    }
}

/// True once every check passed; a failed one is a compile error, so referencing this is enough.
pub const checked = blk: {
    flags(v8.PropertyAttribute, "PropertyAttribute", "None", &.{
        .{ .field = "ReadOnly", .cpp = "ReadOnly" },
        .{ .field = "DontEnum", .cpp = "DontEnum" },
        .{ .field = "DontDelete", .cpp = "DontDelete" },
    });
    flags(v8.PropertyFilter, "PropertyFilter", "ALL_PROPERTIES", &.{
        .{ .field = "OnlyWritable", .cpp = "ONLY_WRITABLE" },
        .{ .field = "OnlyEnumerable", .cpp = "ONLY_ENUMERABLE" },
        .{ .field = "OnlyConfigurable", .cpp = "ONLY_CONFIGURABLE" },
        .{ .field = "SkipStrings", .cpp = "SKIP_STRINGS" },
        .{ .field = "SkipSymbols", .cpp = "SKIP_SYMBOLS" },
    });
    flags(v8.PropertyHandlerFlags, "PropertyHandlerFlags", "kNone", &.{
        .{ .field = "NonMasking", .cpp = "kNonMasking" },
        .{ .field = "OnlyInterceptStrings", .cpp = "kOnlyInterceptStrings" },
        .{ .field = "HasNoSideEffect", .cpp = "kHasNoSideEffect" },
        .{ .field = "HasDontDeleteProperty", .cpp = "kHasDontDeleteProperty" },
        .{ .field = "InternalNewCallbacksSignatures", .cpp = "kInternalNewCallbacksSignatures" },
    });
    flags(v8.String.WriteFlags, "String_WriteFlags", "kNone", &.{
        .{ .field = "NullTerminate", .cpp = "kNullTerminate" },
        .{ .field = "ReplaceInvalidUtf8", .cpp = "kReplaceInvalidUtf8" },
    });
    flags(v8.RegExp.Flags, "RegExp_Flags", "kNone", &.{
        .{ .field = "Global", .cpp = "kGlobal" },
        .{ .field = "IgnoreCase", .cpp = "kIgnoreCase" },
        .{ .field = "Multiline", .cpp = "kMultiline" },
        .{ .field = "Sticky", .cpp = "kSticky" },
        .{ .field = "Unicode", .cpp = "kUnicode" },
        .{ .field = "DotAll", .cpp = "kDotAll" },
        .{ .field = "Linear", .cpp = "kLinear" },
        .{ .field = "HasIndices", .cpp = "kHasIndices" },
        .{ .field = "UnicodeSets", .cpp = "kUnicodeSets" },
    });
    flags(v8.Isolate.MessageErrorLevel, "Isolate_MessageErrorLevel", null, &.{
        .{ .field = "Log", .cpp = "kMessageLog" },
        .{ .field = "Debug", .cpp = "kMessageDebug" },
        .{ .field = "Info", .cpp = "kMessageInfo" },
        .{ .field = "Error", .cpp = "kMessageError" },
        .{ .field = "Warning", .cpp = "kMessageWarning" },
    });
    tags(v8.KeyCollectionMode, "KeyCollectionMode", &.{
        .{ .field = "OwnOnly", .cpp = "kOwnOnly" },
        .{ .field = "IncludePrototypes", .cpp = "kIncludePrototypes" },
    });
    tags(v8.IndexFilter, "IndexFilter", &.{
        .{ .field = "IncludeIndices", .cpp = "kIncludeIndices" },
        .{ .field = "SkipIndices", .cpp = "kSkipIndices" },
    });
    tags(v8.KeyConversionMode, "KeyConversionMode", &.{
        .{ .field = "ConvertToString", .cpp = "kConvertToString" },
        .{ .field = "KeepNumbers", .cpp = "kKeepNumbers" },
        .{ .field = "NoNumbers", .cpp = "kNoNumbers" },
    });
    tags(v8.IntegrityLevel, "IntegrityLevel", &.{
        .{ .field = "Frozen", .cpp = "kFrozen" },
        .{ .field = "Sealed", .cpp = "kSealed" },
    });
    tags(v8.MemoryPressureLevel, "MemoryPressureLevel", &.{
        .{ .field = "None", .cpp = "kNone" },
        .{ .field = "Moderate", .cpp = "kModerate" },
        .{ .field = "Critical", .cpp = "kCritical" },
    });
    tags(v8.SnapshotCreator.FunctionCodeHandling, "SnapshotCreator_FunctionCodeHandling", &.{
        .{ .field = "Clear", .cpp = "kClear" },
        .{ .field = "Keep", .cpp = "kKeep" },
    });
    tags(v8.Isolate.TimeZoneDetection, "Isolate_TimeZoneDetection", &.{
        .{ .field = "Skip", .cpp = "kSkip" },
        .{ .field = "Redetect", .cpp = "kRedetect" },
    });
    if (@as(c_int, @bitCast(v8.Isolate.MessageErrorLevel.all)) != consts.Isolate_MessageErrorLevel_kMessageAll)
        @compileError("Isolate.MessageErrorLevel.all differs from V8's kMessageAll");
    flags(@TypeOf(@as(v8.CTypeInfo, undefined).flags), "CTypeInfo_Flags", "kNone", &.{
        .{ .field = "AllowSharedBit", .cpp = "kAllowSharedBit" },
        .{ .field = "EnforceRangeBit", .cpp = "kEnforceRangeBit" },
        .{ .field = "ClampBit", .cpp = "kClampBit" },
        .{ .field = "IsRestrictedBit", .cpp = "kIsRestrictedBit" },
    });
    break :blk true;
};
