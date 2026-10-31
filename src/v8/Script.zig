const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Context = v8.Context;
const MaybeHandle = v8.MaybeHandle;
const Data = v8.Data;
const Value = v8.Value;
const String = v8.String;
const ScriptOrigin = v8.ScriptOrigin;

pub const Script = extern struct {
    data: Data,

    const Self = @This();

    pub fn from_opaque(o: MaybeHandle) ?Self {
        return .{
            .data = Data.from_opaque(o) orelse return null,
        };
    }

    pub fn compile(context: Context, source: String, origin: ?ScriptOrigin) ?Self {
        const ptr = if (origin) |o| &o.inner else null;
        return @This().from_opaque(e.v8__Script__Compile(context, source, ptr));
    }

    /// Option bit the V8 patch `0011-repl-mode.patch` reads in `CompileUnboundInternal`; it is
    /// outside `ScriptCompiler::CompileOptions` and is removed before V8 sees the options.
    const repl_mode_option: u32 = 1 << 20;

    /// Like `compile`, in REPL mode (the mode of the inspector's `Runtime.evaluate` `replMode`):
    /// a top-level `let`, `const` or `class` may be declared again by a later REPL script, which
    /// replaces the binding, while `const` stays read-only. Requires an entered `context` and a
    /// live handle scope. Borrows `source` and `origin` for this call (V8 copies what it keeps);
    /// the result is a local handle in the current handle scope, null with a pending exception
    /// on a syntax error.
    pub fn compileRepl(context: Context, source: String, origin: ScriptOrigin) ?Self {
        var script_source: v8.ScriptCompiler.Source = undefined;
        v8.ScriptCompiler.Source.init(&script_source, source, &origin, null);
        defer script_source.deinit();
        return v8.ScriptCompiler.compile(context, &script_source, repl_mode_option, 0);
    }

    /// Borrows `self` for this call; returns V8's script id. Retains nothing.
    pub fn scriptId(self: Self) c_int {
        return e.v8__Script__ScriptId(self);
    }

    pub fn run(self: Self, context: Context) ?Value {
        return Value.from_opaque(e.v8__Script__Run(self, context));
    }

    pub fn getUnboundScript(script: v8.Script) ?v8.UnboundScript {
        return v8.UnboundScript.from_opaque(e.v8__Script__GetUnboundScript(script));
    }
};
