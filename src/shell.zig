const std = @import("std");
const v8 = @import("v8.zig");

// Demo js repl.

pub fn main() !void {
    repl();
    std.process.exit(0);
}

fn repl() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var runtime: std.Io.Threaded = .init_single_threaded;
    defer runtime.deinit();

    var input_buf: std.ArrayList(u8) = .empty;
    defer input_buf.deinit(alloc);

    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.initV8Platform(platform);
    defer v8.deinitV8Platform();

    v8.initV8();
    defer _ = v8.deinitV8();

    var params = v8.initCreateParams();
    params.array_buffer_allocator = v8.createDefaultArrayBufferAllocator();
    defer v8.destroyArrayBufferAllocator(params.array_buffer_allocator.?);
    var isolate = v8.Isolate.init(&params);
    defer isolate.deinit();

    isolate.enter();
    defer isolate.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var context = v8.Context.init(isolate, null, null);
    context.enter();
    defer context.exit();

    // context.getGlobal().setValue(ctx: Context, , value: anytype)

    const origin = v8.String.initUtf8(isolate, "(shell)");

    printFmt(
        \\JS Repl
        \\exit with Ctrl+D or "exit()"
        \\
    , .{});

    while (true) {
        input_buf.clearRetainingCapacity();
        printFmt("\n> ", .{});
        var writer = std.Io.Writer.Allocating.fromArrayList(alloc, &input_buf);
        defer writer.deinit();
        if (getInput(runtime.io(), &writer.writer)) {
            const input = writer.written();
            if (std.mem.eql(u8, input, "exit()")) {
                break;
            }

            var res: ExecuteResult = undefined;
            defer res.deinit();
            executeString(alloc, isolate, input, origin, &res);
            if (res.success) {
                printFmt("{s}", .{res.result.?});
            } else {
                printFmt("{s}", .{res.err.?});
            }

            while (platform.pumpMessageLoop(isolate, false)) {
                continue;
            }
        } else {
            printFmt("\n", .{});
            return;
        }
    }
}

fn getInput(io: std.Io, writer: *std.Io.Writer) bool {
    var buffer: [64]u8 = undefined;
    var reader = std.fs.File.stdin().reader(io, &buffer);
    _ = reader.interface.streamDelimiter(writer, '\n') catch |err| {
        if (err == error.EndOfStream) {
            return false;
        } else {
            unreachable;
        }
    };
    return true;
}

pub fn printFmt(comptime format: []const u8, args: anytype) void {
    var buffer: [64]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&buffer);
    writer.interface.print(format, args) catch unreachable;
    writer.interface.flush() catch unreachable;
}

pub const ExecuteResult = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    result: ?[]const u8,
    err: ?[]const u8,
    success: bool,

    pub fn deinit(self: Self) void {
        if (self.result) |result| {
            self.alloc.free(result);
        }
        if (self.err) |err| {
            self.alloc.free(err);
        }
    }
};

pub fn executeString(alloc: std.mem.Allocator, isolate: v8.Isolate, src: []const u8, src_origin: v8.String, result: *ExecuteResult) void {
    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    var try_catch: v8.TryCatch = undefined;
    try_catch.init(isolate);
    defer try_catch.deinit();

    const origin = v8.ScriptOrigin.initDefault(src_origin.toValue());

    const context = isolate.getCurrentContext();

    const js_src = v8.String.initUtf8(isolate, src);

    const script = v8.Script.compile(context, js_src, origin) catch {
        setResultError(alloc, isolate, try_catch, result);
        return;
    };
    const script_res = script.run(context) catch {
        setResultError(alloc, isolate, try_catch, result);
        return;
    };
    result.* = .{
        .alloc = alloc,
        .result = valueToUtf8Alloc(alloc, isolate, context, script_res),
        .err = null,
        .success = true,
    };
}

fn setResultError(alloc: std.mem.Allocator, isolate: v8.Isolate, try_catch: v8.TryCatch, result: *ExecuteResult) void {
    result.* = .{
        .alloc = alloc,
        .result = null,
        .err = getTryCatchErrorString(alloc, isolate, try_catch),
        .success = false,
    };
}

pub fn valueToUtf8Alloc(alloc: std.mem.Allocator, isolate: v8.Isolate, ctx: v8.Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx) catch unreachable;
    const len = str.lenUtf8(isolate);
    const buf = alloc.alloc(u8, len) catch unreachable;
    _ = str.writeUtf8(isolate, buf);
    return buf;
}

pub fn getTryCatchErrorString(alloc: std.mem.Allocator, isolate: v8.Isolate, try_catch: v8.TryCatch) []const u8 {
    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const ctx = isolate.getCurrentContext();

    if (try_catch.getMessage()) |message| {
        var buf: std.ArrayList(u8) = .empty;

        // Append source line.
        const source_line = message.getSourceLine(ctx).?;
        _ = appendValueAsUtf8(alloc, &buf, isolate, ctx, source_line);
        buf.append(alloc, '\n') catch unreachable;

        // Print wavy underline.
        const col_start = message.getStartColumn().?;
        const col_end = message.getEndColumn().?;

        var i: u32 = 0;
        while (i < col_start) : (i += 1) {
            buf.append(alloc, ' ') catch unreachable;
        }
        while (i < col_end) : (i += 1) {
            buf.append(alloc, '^') catch unreachable;
        }
        buf.append(alloc, '\n') catch unreachable;

        if (try_catch.getStackTrace(ctx)) |trace| {
            _ = appendValueAsUtf8(alloc, &buf, isolate, ctx, trace);
            buf.append(alloc, '\n') catch unreachable;
        }

        return buf.toOwnedSlice(alloc) catch unreachable;
    } else {
        // V8 didn't provide any extra information about this error, just get exception str.
        const exception = try_catch.getException().?;
        return valueToUtf8Alloc(alloc, isolate, ctx, exception);
    }
}

pub fn appendValueAsUtf8(alloc: std.mem.Allocator, arr: *std.ArrayList(u8), isolate: v8.Isolate, ctx: v8.Context, any_value: anytype) []const u8 {
    const val = v8.getValue(any_value);
    const str = val.toString(ctx) catch unreachable;
    const len = str.lenUtf8(isolate);
    const start = arr.items.len;
    arr.resize(alloc, start + len) catch unreachable;
    _ = str.writeUtf8(isolate, arr.items[start..arr.items.len]);
    return arr.items[start..];
}
