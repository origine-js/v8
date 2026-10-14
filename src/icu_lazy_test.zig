const std = @import("std");
const v8 = @import("v8.zig");

/// Returns the process-wide publication state by value; retains no resources.
extern fn v8_zig_is_compressed_icu_loaded() bool;

/// Borrows source until return; V8 copies its bytes. Owns an isolate, backing
/// allocator, and local handles, released before return on success or failure.
/// The process V8 platform must remain initialized until this thread returns.
fn evaluate(source: []const u8) bool {
    const aba = v8.ArrayBuffer.Allocator.initDefault();
    defer aba.deinit();
    var params = v8.Isolate.CreateParams.init();
    params.array_buffer_allocator = aba;
    const isolate = v8.Isolate.init(&params);
    defer isolate.deinit();
    isolate.enter();
    defer isolate.exit();
    var h_scope: v8.HandleScope = undefined;
    h_scope.init(isolate);
    defer h_scope.deinit();
    const context = v8.Context.init(isolate, null, null, null);
    context.enter();
    defer context.exit();
    const script = v8.Script.compile(context, v8.String.initUtf8(isolate, source), null) orelse return false;
    return (script.run(context) orelse return false).isTrue();
}

/// Borrows result/gate at stable addresses until this thread joins. Uses only
/// thread-local V8 isolates; publishes a copied boolean and retains no inputs.
fn useIntl(result: *std.atomic.Value(bool), gate: *std.atomic.Value(bool)) void {
    while (!gate.load(.acquire)) std.Thread.yield() catch {};
    result.store(evaluate(
        \\new Intl.NumberFormat('de-DE').format(1234.5) === '1.234,5' &&
        \\new Intl.Collator('de').compare('a', 'z') < 0 &&
        \\new Intl.DateTimeFormat('en', {timeZone:'Asia/Tokyo', hour:'numeric', hourCycle:'h23'}).format(0) === '09' &&
        \\[...new Intl.Segmenter('th', {granularity:'word'}).segment('ภาษาไทย')].length >= 2 &&
        \\'e\u0301'.normalize('NFC') === '\u00e9'
    ), .release);
}

// Owns V8/platform until all worker threads join, including on spawn failure.
// ICU's expanded immutable storage remains process-owned until process exit.
test "ICU: initialization and plain JS stay compressed; concurrent first use loads once" {
    const platform = v8.Platform.initDefault(0, true);
    defer platform.deinit();
    v8.V8.initializePlatform(platform);
    defer v8.V8.disposePlatform();
    v8.V8.initialize();
    defer v8.V8.dispose();
    try std.testing.expect(!v8_zig_is_compressed_icu_loaded());
    try std.testing.expect(v8.V8.initializeICU());
    try std.testing.expect(v8.V8.initializeICU());
    try std.testing.expect(!v8_zig_is_compressed_icu_loaded());
    try std.testing.expect(evaluate("1 + 2 === 3 && Object.isFrozen(Array.prototype)"));
    try std.testing.expect(!v8_zig_is_compressed_icu_loaded());

    var results: [4]std.atomic.Value(bool) = .{ .init(false), .init(false), .init(false), .init(false) };
    var threads: [4]std.Thread = undefined;
    var started: usize = 0;
    var gate: std.atomic.Value(bool) = .init(false);
    defer {
        gate.store(true, .release);
        for (threads[0..started]) |thread| thread.join();
    }
    for (&results, &threads) |*result, *thread| {
        thread.* = try std.Thread.spawn(.{}, useIntl, .{ result, &gate });
        started += 1;
    }
    gate.store(true, .release);
    for (threads) |thread| thread.join();
    started = 0;
    for (&results) |*result| try std.testing.expect(result.load(.acquire));
    try std.testing.expect(v8_zig_is_compressed_icu_loaded());
}
