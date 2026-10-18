const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Handle = v8.Handle;
const MaybeHandle = v8.MaybeHandle;

pub const Data = extern struct {
    handle: Handle,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .handle = @ptrCast(o orelse return null),
        };
    }

    pub fn eq(self: @This(), other: @This()) bool {
        return e.v8__Data__EQ(self, other);
    }

    pub fn isBigInt(self: @This()) bool {
        return e.v8__Data__IsBigInt(self);
    }

    pub fn isBoolean(self: @This()) bool {
        return e.v8__Data__IsBoolean(self);
    }

    pub fn isContext(self: @This()) bool {
        return e.v8__Data__IsContext(self);
    }

    pub fn isFixedArray(self: @This()) bool {
        return e.v8__Data__IsFixedArray(self);
    }

    pub fn isFunctionTemplate(self: @This()) bool {
        return e.v8__Data__IsFunctionTemplate(self);
    }

    pub fn isModule(self: @This()) bool {
        return e.v8__Data__IsModule(self);
    }

    pub fn isModuleRequest(self: @This()) bool {
        return e.v8__Data__IsModuleRequest(self);
    }

    pub fn isName(self: @This()) bool {
        return e.v8__Data__IsName(self);
    }

    pub fn isNumber(self: @This()) bool {
        return e.v8__Data__IsNumber(self);
    }

    pub fn isObjectTemplate(self: @This()) bool {
        return e.v8__Data__IsObjectTemplate(self);
    }

    pub fn isPrimitive(self: @This()) bool {
        return e.v8__Data__IsPrimitive(self);
    }

    pub fn isPrivate(self: @This()) bool {
        return e.v8__Data__IsPrivate(self);
    }

    pub fn isString(self: @This()) bool {
        return e.v8__Data__IsString(self);
    }

    pub fn isSymbol(self: @This()) bool {
        return e.v8__Data__IsSymbol(self);
    }

    pub fn isValue(self: @This()) bool {
        return e.v8__Data__IsValue(self);
    }
};
