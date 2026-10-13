const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Context = v8.Context;
const Value = v8.Value;
const String = v8.String;
const StackTrace = v8.StackTrace;

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

    pub fn isOpaque(self: v8.Message) bool {
        return e.v8__Message__IsOpaque(self.handle);
    }
};
