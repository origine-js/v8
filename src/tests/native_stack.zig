const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const Env = @import("raw/support.zig").Env;

test "Context: native stack limit ignores JavaScript values and getters" {
    // Configure the construction exception before flags freeze at V8 initialization.
    // This dedicated process never exposes its mutable context to another test.
    v8.V8.setFlagsFromString("--no-zig-harden-intrinsics --harmony-shadow-realm");
    var env: Env = undefined;
    env.start();
    defer env.stop();
    try t.expect(env.eval("typeof WebAssembly === 'object' && typeof ShadowRealm === 'undefined'").isTrue());
    env.context.setStackTraceLimit(.{ .limited = 2 });
    try t.expect(env.eval(
        \\globalThis.accessed = 0;
        \\Object.defineProperty(Error, 'stackTraceLimit', {
        \\  configurable: true, get() { accessed++; throw new Error('forged'); }
        \\});
        \\globalThis.capture = function descend(n) { return n ? descend(n - 1) : new Error('native'); };
        \\globalThis.frames = error => error.stack.split('\n').length - 1;
        \\frames(capture(24)) === 2 && accessed === 0
    ).isTrue());
    env.context.setStackTraceLimit(.unlimited);
    try t.expect(env.context.getStackTraceLimit() == .unlimited);
    try t.expect(env.eval("frames(capture(24)) > 20 && accessed === 0").isTrue());
    env.context.setStackTraceLimit(.none);
    try t.expect(env.eval("frames(capture(24)) === 0 && accessed === 0").isTrue());
    try t.expect(env.eval("Object.defineProperty(Error, 'stackTraceLimit', {value: 99}); frames(capture(24)) === 0").isTrue());
}
