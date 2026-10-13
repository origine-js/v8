const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const String = v8.String;
const StackFrame = v8.StackFrame;

pub const StackTrace = struct {
    pub const Opaque = opaque {};

    handle: *const Opaque,

    const Self = @This();

    pub fn getFrameCount(self: Self) c_int {
        return e.v8__StackTrace__GetFrameCount(self.handle);
    }

    pub fn getFrame(self: Self, isolate: Isolate, index: u32) StackFrame {
        return .{
            .handle = e.v8__StackTrace__GetFrame(self.handle, isolate.handle, index).?,
        };
    }

    pub fn getCurrentStackTrace(isolate: Isolate, frame_limit: c_int) StackTrace {
        return .{
            .handle = e.v8__StackTrace__CurrentStackTrace(isolate.handle, frame_limit).?,
        };
    }

    pub fn getCurrentScriptNameOrSourceUrl(isolate: Isolate) ?String {
        if (e.v8__StackTrace__CurrentScriptNameOrSourceURL(isolate.handle)) |ptr| {
            return String.from_opaque(ptr);
        }
        return null;
    }
    pub fn from_opaque(o: ?*const Opaque) ?@This() {
        return .{ .handle = o orelse return null };
    }
};
