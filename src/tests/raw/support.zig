const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
pub const ensureV8 = @import("../support.zig").ensureV8;

pub const Env = struct {
    aba: v8.ArrayBuffer.Allocator,
    params: v8.Isolate.CreateParams,
    isolate: v8.Isolate,
    h_scope: v8.HandleScope,
    context: v8.Context,

    /// Owns an isolate and backing allocator until stop; self must remain at this
    /// address with its entered context and HandleScope live. Initialization is fatal on V8 OOM.
    pub fn start(self: *Env) void {
        ensureV8();
        self.params = .init();
        self.aba = .initDefault();
        self.params.array_buffer_allocator = self.aba;
        self.isolate = .init(&self.params);
        self.isolate.enter();
        self.h_scope.init(self.isolate);
        self.context = .init(self.isolate, null, null, null);
        self.context.enter();
    }

    /// Consumes fixture-owned context/HandleScope, isolate and backing allocator
    /// in reverse order. Invalidates all local handles; call on the thread that called start.
    pub fn stop(self: *Env) void {
        self.context.exit();
        self.h_scope.deinit();
        self.isolate.exit();
        self.isolate.deinit();
        self.aba.deinit();
    }

    /// Borrows self and immutable bytes through return; V8 copies the bytes.
    /// Returns a local string valid until this fixture stops or its enclosing HandleScope closes.
    pub fn str(self: *Env, s: []const u8) v8.String {
        return .initUtf8(self.isolate, s);
    }

    /// Borrows self and immutable bytes through return; returns a local name
    /// valid until this fixture stops or its enclosing HandleScope closes. Retains no input bytes.
    pub fn name(self: *Env, s: []const u8) v8.Name {
        return self.str(s).name;
    }

    /// Borrows self/source through return; returns a local value valid until stop.
    /// Caller keeps this fixture entered; null retains nothing on JS failure.
    pub fn tryEval(self: *Env, src: []const u8) ?v8.Value {
        const script = v8.Script.compile(self.context, self.str(src), null) orelse return null;
        return script.run(self.context);
    }

    /// Borrows self/source through return; returns a local value valid until
    /// stop. Requires the fixture entered; a JavaScript exception is fatal to this test.
    pub fn eval(self: *Env, src: []const u8) v8.Value {
        return self.tryEval(src) orelse @panic("script threw");
    }

    /// Borrows self/value through conversion; returns bytes owned by t.allocator.
    /// Caller frees the result; allocation failure retains nothing.
    pub fn utf8(self: *Env, value: v8.Value) ![]u8 {
        const s = value.toString(self.context).?;
        const buf = try t.allocator.alloc(u8, s.lenUtf8(self.isolate));
        _ = s.writeUtf8(self.isolate, buf);
        return buf;
    }

    /// Borrows self/source/expected through return; releases temporary UTF-8
    /// storage on success and assertion failure. All local values expire at stop.
    pub fn expectEval(self: *Env, src: []const u8, expected: []const u8) !void {
        const got = try self.utf8(self.eval(src));
        defer t.allocator.free(got);
        try t.expectEqualStrings(expected, got);
    }

    /// Borrows key/value through return; V8 copies the key and the context
    /// retains the value until collected or disposed. Requires the fixture entered.
    pub fn setGlobal(self: *Env, key: []const u8, value: v8.Value) void {
        _ = self.context.getGlobal().set(self.context, self.name(key).primitive.value, value);
    }
};

/// Owns the stable fixture through body and destroys it on success/error.
/// Borrows body only through return; body must not retain the fixture or its local handles.
pub fn withEnv(comptime body: fn (*Env) anyerror!void) !void {
    var env: Env = undefined;
    env.start();
    defer env.stop();
    try body(&env);
}

/// Borrows env through return; returns a local number in its live HandleScope.
/// The number expires when that HandleScope closes; retains no host resources.
pub fn num(env: *Env, n: i32) v8.Value {
    return v8.Number.initInt(env.isolate, n).numeric.primitive.value;
}
