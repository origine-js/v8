const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const String = v8.String;

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

    pub fn getScriptSource(self: v8.StackFrame) ?v8.String {
        return v8.String.from_opaque(e.v8__StackFrame__GetScriptSource(self.handle));
    }

    pub fn getScriptSourceMappingURL(self: v8.StackFrame) ?v8.String {
        return v8.String.from_opaque(e.v8__StackFrame__GetScriptSourceMappingURL(self.handle));
    }
};
