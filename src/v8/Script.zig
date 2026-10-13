const e = @import("../externs.gen.zig");
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

    pub fn run(self: Self, context: Context) ?Value {
        return Value.from_opaque(e.v8__Script__Run(self, context));
    }

    pub fn getUnboundScript(script: v8.Script) ?v8.UnboundScript {
        return v8.UnboundScript.from_opaque(e.v8__Script__GetUnboundScript(script));
    }
};
