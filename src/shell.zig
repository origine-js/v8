const std = @import("std");
const v8 = @import("v8.zig");
const m = @import("./managed.zig");

// Demo js repl.

// comptime {
//     _ = @import("./alloc.zig");
// }

fn double(x: i32) i32 {
    return x + x;
}

pub fn main() !void {
    repl();
    std.process.exit(0);
}

var runtime: std.Io.Threaded = undefined;

fn hello_fn(info: v8.FunctionCallbackInfo) callconv(.c) void {
    // var hscope: v8.HandleScope = undefined;
    // hscope.init(info.isolate());
    // defer hscope.deinit();
    const arg_length = info.length();
    std.debug.print("arg length: {}\n", .{arg_length});
    const isolate = info.isolate();
    const ctx = isolate.getCurrentContext();
    var idx: c_int = 0;
    var arr: std.ArrayList(u8) = .empty;
    defer arr.deinit(std.heap.smp_allocator);
    while (idx < arg_length) : (idx += 1) {
        arr.clearRetainingCapacity();
        const s = appendValueAsUtf8(std.heap.smp_allocator, &arr, isolate, ctx, info.get_arg(idx));
        std.debug.print("arg {} = {s}\n", .{ idx, s });
    }
    var retval = info.retval();
    retval.setBool(true);
}

fn create_api(isolate: v8.Isolate) v8.ObjectTemplate {
    var impl = v8.ObjectTemplate.initDefault(isolate).?;

    // _ = impl.template.set(js_name, v8.Number.initInt(isolate, 1).numeric.primitive.value.data, .{
    //     .DontDelete = true,
    //     .ReadOnly = true,
    // });
    var builder: v8.FunctionTemplate.Builder = .{};
    _ = impl.template.set(v8.String.initOneByte(isolate, "inspect").name, builder.build(isolate, &hello_fn, &.{}).template.data, .{
        .DontDelete = true,
        .ReadOnly = true,
    });

    return impl;
}

fn setup_global(isolate: v8.Isolate, ctx: v8.Context) void {
    const global = ctx.getGlobal();
    var js_name: v8.Name = v8.String.initOneByte(isolate, "core").name;
    _ = global.set(ctx, js_name.primitive.value, create_api(isolate).initInstance(ctx).?.value);
}

fn repl() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    runtime = .init(gpa.allocator());
    defer runtime.deinit();

    var input_buf: std.ArrayList(u8) = .empty;
    defer input_buf.deinit(alloc);

    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();

    v8.V8.initializePlatform(platform);

    v8.V8.initialize();
    defer _ = v8.V8.dispose();

    var rt: m.Runtime = .init(alloc);
    defer rt.deinit();

    rt.isolate.enter();
    defer rt.isolate.exit();

    var hscope: v8.HandleScope = undefined;
    hscope.init(rt.isolate);
    defer hscope.deinit();

    var context: v8.Context = rt.context();
    context.enter();
    defer context.exit();

    setup_global(rt.isolate, context);

    const origin = v8.String.initUtf8(rt.isolate, "(shell)");

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
            executeString(alloc, &rt, input, origin, &res);
            if (res.success) {
                printFmt("{s}", .{res.result.?});
            } else {
                printFmt("{s}", .{res.err.?});
            }

            while (platform.pumpMessageLoop(rt.isolate, false)) {
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

pub fn executeString(alloc: std.mem.Allocator, rt: *m.Runtime, src: []const u8, src_origin: v8.String, result: *ExecuteResult) void {
    var hscope: v8.HandleScope = undefined;
    hscope.init(rt.isolate);
    defer hscope.deinit();

    var tc_scope: v8.TryCatch = undefined;
    tc_scope.init(rt.isolate);
    defer tc_scope.deinit();

    const origin = rt.script_origin(
        src_origin.name.primitive.value,
        0,
        0,
        false,
        -1,
        null,
        false,
        false,
        false,
    );

    const context = rt.isolate.getCurrentContext();

    const js_src = v8.String.initUtf8(rt.isolate, src);

    const script = v8.Script.compile(context, js_src, origin) orelse {
        setResultError(alloc, rt.isolate, tc_scope, result);
        return;
    };
    const script_res = script.run(context) orelse {
        setResultError(alloc, rt.isolate, tc_scope, result);
        return;
    };
    result.* = .{
        .alloc = alloc,
        .result = valueToUtf8Alloc(alloc, rt.isolate, context, script_res),
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

pub fn valueToUtf8Alloc(alloc: std.mem.Allocator, isolate: v8.Isolate, ctx: v8.Context, val: v8.Value) []const u8 {
    const str = val.toString(ctx) orelse unreachable;
    const len = str.lenUtf8(isolate);
    const buf = alloc.alloc(u8, len) catch unreachable;
    _ = str.writeUtf8(isolate, buf);
    return buf;
}

pub fn getTryCatchErrorString(alloc: std.mem.Allocator, isolate: v8.Isolate, tc_scope: v8.TryCatch) []const u8 {
    var hscope: v8.HandleScope = undefined;
    hscope.init(isolate);
    defer hscope.deinit();

    const ctx = isolate.getCurrentContext();

    var buf: std.ArrayList(u8) = .empty;
    if (tc_scope.getMessage()) |message| {
        buf.clearRetainingCapacity();

        // Append source line.
        const source_line = message.getSourceLine(ctx).?;
        _ = appendValueAsUtf8(alloc, &buf, isolate, ctx, source_line.name.primitive.value);
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

        if (tc_scope.getStackTrace(ctx)) |trace| {
            _ = appendValueAsUtf8(alloc, &buf, isolate, ctx, trace);
            buf.append(alloc, '\n') catch unreachable;
        }

        return buf.toOwnedSlice(alloc) catch unreachable;
    } else {
        // V8 didn't provide any extra information about this error, just get exception str.
        const exception = tc_scope.getException().?;
        return valueToUtf8Alloc(alloc, isolate, ctx, exception);
    }
}

pub fn appendValueAsUtf8(alloc: std.mem.Allocator, arr: *std.ArrayList(u8), isolate: v8.Isolate, ctx: v8.Context, val: v8.Value) []const u8 {
    const str = val.toString(ctx) orelse unreachable;
    const len = str.lenUtf8(isolate);
    arr.ensureTotalCapacityPrecise(alloc, len) catch unreachable;
    const buf = arr.addManyAsSliceAssumeCapacity(len);
    const actual_len = str.writeUtf8(
        isolate,
        buf,
    );
    std.debug.assert(len == actual_len);
    return buf;
}
