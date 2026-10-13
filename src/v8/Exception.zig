const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const Exception = extern struct {
    pub fn rangeError(message: v8.String) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Exception__RangeError(message));
    }

    pub fn referenceError(message: v8.String) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Exception__ReferenceError(message));
    }

    pub fn syntaxError(message: v8.String) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Exception__SyntaxError(message));
    }

    pub fn typeError(message: v8.String) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Exception__TypeError(message));
    }

    pub fn @"error"(message: v8.String) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Exception__Error(message));
    }

    pub fn createMessage(isolate: v8.Isolate, exception: v8.Value) ?v8.Message {
        return .{ .handle = e.v8__Exception__CreateMessage(isolate.handle, exception) orelse return null };
    }

    pub fn getStackTrace(exception: v8.Value) ?v8.StackTrace {
        return v8.StackTrace.from_opaque(e.v8__Exception__GetStackTrace(exception));
    }

    pub fn captureStackTrace(context: v8.Context, object: v8.Object) ?bool {
        return e.v8__Exception__CaptureStackTrace(context, object).as_optional();
    }
};
