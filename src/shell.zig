//! Native scope demo: all module bytes come from memory.
const std = @import("std");
const v8 = @import("v8.zig");
const m = @import("managed.zig");
const mimalloc = @import("mimalloc.zig");
var io_runtime: std.Io.Threaded = undefined;

const StartupTrace = struct {
    enabled: bool,
    last: i64,
    count: usize = 0,
    samples: [16]struct { name: []const u8, ns: i64 } = undefined,

    /// Reads the process monotonic clock; retains no resources. Clock failure is fatal.
    fn now() i64 {
        var ts: std.c.timespec = undefined;
        if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts) != 0) @panic("startup clock failed");
        return @as(i64, @intCast(ts.sec)) * 1_000_000_000 + @as(i64, @intCast(ts.nsec));
    }

    /// Reads but does not retain environment storage; returns an owning inline trace.
    fn init() StartupTrace {
        return .{ .enabled = std.c.getenv("V8_STARTUP_TRACE") != null, .last = now() };
    }

    /// Borrows self through this call and retains static name until report; allocates nothing.
    fn mark(self: *StartupTrace, comptime name: []const u8) void {
        if (!self.enabled) return;
        const time = now();
        self.samples[self.count] = .{ .name = name, .ns = time - self.last };
        self.count += 1;
        self.last = time;
    }

    /// Borrows recorded samples through this call; writes stderr after startup so
    /// reporting I/O is excluded from stage times. Retains no resources.
    fn report(self: *const StartupTrace) void {
        if (!self.enabled) return;
        var total: i64 = 0;
        for (self.samples[0..self.count]) |sample| {
            std.debug.print("startup {s}: {d} ns\n", .{ sample.name, sample.ns });
            total += sample.ns;
        }
        std.debug.print("startup total: {d} ns\n", .{total});
    }
};

fn print(comptime format: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io_runtime.io(), &buffer);
    writer.interface.print(format, args) catch return;
    writer.interface.flush() catch return;
}

fn load(_: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
    if (request.import_attributes.len != 0) {
        return .{ .exception = v8.Exception.typeError(v8.String.initUtf8(v8.Isolate.getCurrent(), "The demo loader does not support import attributes")).? };
    }
    if (std.mem.eql(u8, request.module_id, "app:/one.js")) return .{ .source = "export const value = 'scope A';" };
    if (std.mem.eql(u8, request.module_id, "app:/two.js")) return .{ .source = "export const value = 'scope B';" };
    return error.ModuleNotFound;
}

/// Borrows scope/value through string conversion; caller keeps the runtime alive.
/// Local V8 handles and UTF-8 storage are released before return.
fn show(scope: *m.Scope, value: v8.Global.Of(v8.Value)) void {
    const isolate = scope.runtime.isolate;
    isolate.enter();
    defer isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(isolate);
    defer h_scope.deinit();
    const ctx = scope.context.deref();
    ctx.enter();
    defer ctx.exit();
    // toString may invoke arbitrary guest code, including a throwing getter.
    var tc_scope: v8.TryCatch = undefined;
    tc_scope.init(isolate);
    defer tc_scope.deinit();
    const text = value.deref().toString(ctx) orelse {
        print("<value conversion threw>\n", .{});
        return;
    };
    const buffer = std.heap.smp_allocator.alloc(u8, text.lenUtf8(isolate)) catch return;
    defer std.heap.smp_allocator.free(buffer);
    const length = text.writeUtf8(isolate, buffer);
    print("{s}\n", .{buffer[0..length]});
}

/// Owns the demo engine/runtime and host allocations until exit; releases all V8
/// values before teardown. Uses process-lifetime mimalloc for ArrayBuffer backing stores.
/// Owns one V8 background worker until platform teardown; foreground jobs are
/// pumped on the calling thread. No callback state escapes runtime teardown.
pub fn main() !void {
    var startup = StartupTrace.init();
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const alloc = debug_allocator.allocator();
    io_runtime = .init(alloc, .{});
    defer io_runtime.deinit();
    startup.mark("host_io");
    const platform = v8.Platform.initDefault(1, true);
    startup.mark("platform_create");
    defer platform.deinit();
    v8.V8.initializePlatform(platform);
    defer v8.V8.disposePlatform();
    v8.V8.initialize();
    defer _ = v8.V8.dispose();
    startup.mark("v8_initialize");
    var rt = try m.Runtime.initWithOptions(alloc, .{ .array_buffer_allocator = .{ .zig = mimalloc.allocator } });
    startup.mark("runtime_isolate");
    defer rt.deinit();
    var map_a = try m.ImportMap.init(alloc, .{
        .base_url = "app:/map.json",
        .urls = m.virtual_urls,
        .imports = &.{.{
            .key = "demo",
            .target = "./one.js",
        }},
    });
    defer map_a.deinit();
    var map_b = try m.ImportMap.init(alloc, .{
        .base_url = "app:/map.json",
        .urls = m.virtual_urls,
        .imports = &.{.{
            .key = "demo",
            .target = "./two.js",
        }},
    });
    defer map_b.deinit();
    startup.mark("import_maps");
    const a = try rt.createScope(.{
        .import_map = &map_a,
        .loader = .{ .load = load },
    });
    startup.mark("scope_a");
    const b = try rt.createScope(.{
        .import_map = &map_b,
        .loader = .{ .load = load },
    });
    startup.mark("scope_b");
    const counter = try a.eval("new (class Counter { #value = 0; inc(){return ++this.#value} get value(){return this.#value} })()", "app:/counter.js", null);
    defer counter.deinit();
    try a.installCapability("counter", counter, null);
    try b.installCapability("counter", counter, null);
    startup.mark("counter_capabilities");
    for ([_]*m.Scope{ a, b }) |scope| {
        const setup = try scope.eval("globalThis.moduleValue = ''; import('demo').then(m => { moduleValue = m.value }); 'ready'", "app:/setup.js", null);
        setup.deinit();
    }
    rt.pump();
    startup.mark("module_imports_pump");
    startup.report();
    @import("startup_trace.zig").report();
    print(
        \\Native V8 scopes: :a / :b switches scope; exit() or Ctrl+D exits.
        \\Try moduleValue, counter.inc(), counter.value, or Object.prototype.x = 1.
        \\
    , .{});
    var current = a;
    var input_buffer: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io_runtime.io(), &input_buffer);
    while (true) {
        print("{s}> ", .{if (current == a) "A" else "B"});
        const line = (reader.interface.takeDelimiter('\n') catch |err| {
            print("Input error: {s}\n", .{@errorName(err)});
            return;
        }) orelse break;
        const input = std.mem.trim(u8, line, " \r\t");
        if (std.mem.eql(u8, input, "exit()")) break;
        if (std.mem.eql(u8, input, ":a")) {
            current = a;
            continue;
        }
        if (std.mem.eql(u8, input, ":b")) {
            current = b;
            continue;
        }
        var error_info: m.ErrorInfo = .{};
        defer error_info.deinit();
        const result = current.eval(input, "app:/shell.js", &error_info) catch |err| {
            print("Evaluation failed: {s}\n", .{@errorName(err)});
            if (error_info.exception) |value| show(current, value);
            continue;
        };
        defer result.deinit();
        show(current, result);
        rt.pumpPlatform(platform);
    }
}
