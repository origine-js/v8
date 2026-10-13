const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const MaybeHandle = v8.MaybeHandle;
const Isolate = v8.Isolate;
const Context = v8.Context;
const String = v8.String;
const Value = v8.Value;
const Name = v8.Name;

pub const Symbol = extern struct {
    name: Name,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{ .name = Name.from_opaque(o) orelse return null };
    }

    pub fn init(isolate: Isolate, desc: ?String) @This() {
        return from_opaque(e.v8__Symbol__New(isolate.handle, descHandle(desc))).?;
    }

    /// Global-registry symbol (`Symbol.for`) of the isolate.
    pub fn @"for"(isolate: Isolate, desc: String) @This() {
        return from_opaque(e.v8__Symbol__For(isolate.handle, desc)).?;
    }

    pub fn forApi(isolate: Isolate, desc: String) @This() {
        return from_opaque(e.v8__Symbol__ForApi(isolate.handle, desc)).?;
    }

    /// The description, or `undefined`.
    pub fn description(self: @This(), isolate: Isolate) Value {
        return Value.from_opaque(e.v8__Symbol__Description(self, isolate.handle)).?;
    }

    fn descHandle(s: ?String) MaybeHandle {
        return (s orelse return null).name.primitive.value.data.handle;
    }

    pub fn getAsyncIterator(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetAsyncIterator(isolate.handle)).?;
    }

    pub fn getHasInstance(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetHasInstance(isolate.handle)).?;
    }

    pub fn getIsConcatSpreadable(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetIsConcatSpreadable(isolate.handle)).?;
    }

    pub fn getIterator(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetIterator(isolate.handle)).?;
    }

    pub fn getMatch(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetMatch(isolate.handle)).?;
    }

    pub fn getReplace(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetReplace(isolate.handle)).?;
    }

    pub fn getSearch(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetSearch(isolate.handle)).?;
    }

    pub fn getSplit(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetSplit(isolate.handle)).?;
    }

    pub fn getToPrimitive(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetToPrimitive(isolate.handle)).?;
    }

    pub fn getToStringTag(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetToStringTag(isolate.handle)).?;
    }

    pub fn getUnscopables(isolate: Isolate) @This() {
        return from_opaque(e.v8__Symbol__GetUnscopables(isolate.handle)).?;
    }
};
