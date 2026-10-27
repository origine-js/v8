const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const Template = v8.Template;
const Context = v8.Context;
const Object = v8.Object;

pub const ObjectTemplate = extern struct {
    template: Template,

    pub fn initDefault(isolate: Isolate) ?@This() {
        return .{
            .template = Template.from_opaque(e.v8__ObjectTemplate__New__DEFAULT(isolate.handle)) orelse return null,
        };
    }

    pub fn initInstance(self: @This(), context: Context) ?Object {
        return .from_opaque(e.v8__ObjectTemplate__NewInstance(self, context));
    }

    pub fn init(isolate: v8.Isolate, templ: v8.FunctionTemplate) ?v8.ObjectTemplate {
        return v8.ObjectTemplate.from_opaque(e.v8__ObjectTemplate__New(isolate.handle, templ));
    }

    pub fn internalFieldCount(self: v8.ObjectTemplate) c_int {
        return e.v8__ObjectTemplate__InternalFieldCount(self);
    }

    pub fn setInternalFieldCount(self: v8.ObjectTemplate, value: c_int) void {
        e.v8__ObjectTemplate__SetInternalFieldCount(self, value);
    }

    pub fn setNativeDataProperty(self: v8.ObjectTemplate, key: v8.Name, getter: v8.AccessorNameGetterCallback, setter: v8.AccessorNameSetterCallback, data_or_null: ?v8.Value, attr: v8.PropertyAttribute) void {
        e.v8__ObjectTemplate__SetNativeDataProperty(self, key, getter, setter, if (data_or_null) |v| v8.support.rawHandle(v) else null, attr);
    }

    pub fn setNamedPropertyHandler(self: v8.ObjectTemplate, getter: v8.Callbacks.NamedPropertyGetterCallback, setter: v8.Callbacks.NamedPropertySetterCallback, query: v8.Callbacks.NamedPropertyQueryCallback, deleter: v8.Callbacks.NamedPropertyDeleterCallback, enumerator: v8.Callbacks.NamedPropertyEnumeratorCallback, definer: v8.Callbacks.NamedPropertyDefinerCallback, descriptor: v8.Callbacks.NamedPropertyDescriptorCallback, data_or_null: ?v8.Value, flags: v8.PropertyHandlerFlags) void {
        e.v8__ObjectTemplate__SetNamedPropertyHandler(self, getter, setter, query, deleter, enumerator, definer, descriptor, if (data_or_null) |v| v8.support.rawHandle(v) else null, flags);
    }

    pub fn setIndexedPropertyHandler(self: v8.ObjectTemplate, getter: v8.Callbacks.IndexedPropertyGetterCallbackV2, setter: v8.Callbacks.IndexedPropertySetterCallbackV2, query: v8.Callbacks.IndexedPropertyQueryCallbackV2, deleter: v8.Callbacks.IndexedPropertyDeleterCallbackV2, enumerator: v8.Callbacks.IndexedPropertyEnumeratorCallback, definer: v8.Callbacks.IndexedPropertyDefinerCallbackV2, descriptor: v8.Callbacks.IndexedPropertyDescriptorCallbackV2, data_or_null: ?v8.Value, flags: v8.PropertyHandlerFlags) void {
        e.v8__ObjectTemplate__SetIndexedPropertyHandler(self, getter, setter, query, deleter, enumerator, definer, descriptor, if (data_or_null) |v| v8.support.rawHandle(v) else null, flags);
    }

    pub fn setAccessorProperty(self: v8.ObjectTemplate, key: v8.Name, getter: v8.FunctionTemplate, setter: v8.FunctionTemplate, attr: v8.PropertyAttribute) void {
        e.v8__ObjectTemplate__SetAccessorProperty(self, key, getter, setter, attr);
    }

    pub fn setImmutableProto(self: v8.ObjectTemplate) void {
        e.v8__ObjectTemplate__SetImmutableProto(self);
    }
    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .template = v8.Template.from_opaque(o) orelse return null };
    }
};
