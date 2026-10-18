const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const FunctionCallback = v8.FunctionCallback;
const ConstructorBehavior = v8.ConstructorBehavior;
const SideEffectType = v8.SideEffectType;
const Context = v8.Context;
const MaybeHandle = v8.MaybeHandle;
const Data = v8.Data;
const Value = v8.Value;
const Object = v8.Object;
const String = v8.String;
const ScriptOrigin = v8.ScriptOrigin;

pub const Function = extern struct {
    object: Object,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .object = Object.from_opaque(o) orelse return null,
        };
    }

    pub fn init(
        context: Context,
        callback: FunctionCallback,
        maybe_data: ?Data,
        length: c_int,
        constructor_behavior: ConstructorBehavior,
        side_effect_type: SideEffectType,
    ) Function {
        return Function.from_opaque(e.v8__Function__New(
            context,
            callback,
            if (maybe_data) |v| v.handle else null,
            length,
            constructor_behavior,
            side_effect_type,
        )).?;
    }

    pub fn getName(self: @This()) Value {
        return Value.from_opaque(e.v8__Function__GetName(self)).?;
    }

    pub fn setName(self: @This(), name: String) void {
        e.v8__Function__SetName(self, name);
    }

    pub fn getScriptColumnNumber(self: @This()) c_int {
        return e.v8__Function__GetScriptColumnNumber(self);
    }
    pub fn getScriptLineNumber(self: @This()) c_int {
        return e.v8__Function__GetScriptLineNumber(self);
    }
    pub fn scriptId(self: Function) c_int {
        return e.v8__Function__ScriptId(self);
    }
    pub fn getScriptOrigin(self: Function) ScriptOrigin {
        const origin = e.v8__Function__GetScriptOrigin(self).?;
        defer e.v8__ScriptOrigin__DELETE(@constCast(origin));
        return .{ .inner = origin.* };
    }

    pub fn call(self: v8.Function, context: v8.Context, recv: v8.Value, args: []const v8.Value) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Function__Call(self, context, recv, @intCast(args.len), @ptrCast(args.ptr)));
    }

    pub fn newInstance(self: v8.Function, context: v8.Context, args: []const v8.Value) ?v8.Object {
        return v8.Object.from_opaque(e.v8__Function__NewInstance(self, context, @intCast(args.len), @ptrCast(args.ptr)));
    }

    pub fn createCodeCache(self: v8.Function) ?v8.ScriptCompiler.CachedData {
        return .{ .handle = e.v8__Function__CreateCodeCache(self) orelse return null };
    }
};
