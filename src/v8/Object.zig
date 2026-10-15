const std = @import("std");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const V8 = v8.V8;
const Isolate = v8.Isolate;
const AccessorNameGetterCallback = v8.AccessorNameGetterCallback;
const AccessorNameSetterCallback = v8.AccessorNameSetterCallback;
const PropertyDescriptor = v8.PropertyDescriptor;
const PropertyAttribute = v8.PropertyAttribute;
const Context = v8.Context;
const MaybeHandle = v8.MaybeHandle;
const Value = v8.Value;
const Primitive = v8.Primitive;
const Name = v8.Name;
const String = v8.String;

pub const Object = extern struct {
    value: Value,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .value = Value.from_opaque(o) orelse return null,
        };
    }

    pub fn init(isolate: Isolate) Object {
        return from_opaque(e.v8__Object__New(isolate.handle)).?;
    }

    /// `prototype` is a required object, or JS `null` (`Primitive.initNull`) for none;
    /// V8 rejects an empty handle.
    pub fn initWithProperties(
        isolate: Isolate,
        prototype: Value,
        names: []const Name,
        values: []const Value,
    ) Object {
        std.debug.assert(names.len == values.len);
        return from_opaque(e.v8__Object__New__with_prototype_and_properties(
            isolate.handle,
            prototype,
            // Name/Value are one-pointer wrappers, layout-identical to a handle array.
            @ptrCast(names.ptr),
            @ptrCast(values.ptr),
            names.len,
        )).?;
    }

    pub fn get(self: Object, context: Context, key: Value) ?Value {
        return Value.from_opaque(e.v8__Object__Get(self, context, key));
    }

    pub fn getWithReceiver(self: Object, context: Context, key: Value, receiver: Object) ?Value {
        return Value.from_opaque(e.v8__Object__GetWithReceiver(self, context, key, receiver));
    }

    pub fn getIndex(self: Object, context: Context, index: u32) ?Value {
        return Value.from_opaque(e.v8__Object__GetIndex(self, context, index));
    }

    pub fn getAlignedPointerFromInternalField(self: Object, index: c_int) ?*anyopaque {
        return e.v8__Object__GetAlignedPointerFromInternalField(self, index);
    }

    pub fn setAlignedPointerInInternalField(self: Object, index: c_int, value: ?*anyopaque) void {
        e.v8__Object__SetAlignedPointerInInternalField(self, index, value);
    }

    /// Borrows `self` for this call; true if the object can be called as a function. Retains nothing.
    pub fn isCallable(self: Object) bool {
        return e.v8__Object__IsCallable(self);
    }

    /// Borrows `self` for this call; true if the object can be used with `new`. Retains nothing.
    pub fn isConstructor(self: Object) bool {
        return e.v8__Object__IsConstructor(self);
    }

    pub fn isApiWrapper(self: Object) bool {
        return e.v8__Object__IsApiWrapper(self);
    }

    pub fn getPrototype(self: Object) ?Value {
        return Value.from_opaque(e.v8__Object__GetPrototype(self));
    }

    pub fn set(self: Object, context: Context, key: Value, value: Value) ?bool {
        return e.v8__Object__Set(self, context, key, value).as_optional();
    }

    pub fn setWithReceiver(self: Object, context: Context, key: Value, value: Value, receiver: Object) ?bool {
        return e.v8__Object__SetWithReceiver(self, context, key, value, receiver).as_optional();
    }

    pub fn setIndex(self: Object, context: Context, index: u32, value: Value) ?bool {
        return e.v8__Object__SetIndex(self, context, index, value).as_optional();
    }

    pub fn setPrototype(self: Object, context: Context, prototype: Value) ?bool {
        return e.v8__Object__SetPrototype(self, context, prototype).as_optional();
    }

    pub fn getConstructorName(self: Object) String {
        return String.from_opaque(e.v8__Object__GetConstructorName(self)).?;
    }

    pub fn createDataProperty(self: Object, context: Context, key: Name, value: Value) ?bool {
        return e.v8__Object__CreateDataProperty(self, context, key, value).as_optional();
    }

    pub fn defineOwnProperty(self: Object, context: Context, key: Name, value: Value, attr: PropertyAttribute) ?bool {
        return e.v8__Object__DefineOwnProperty(self, context, key, value, attr).as_optional();
    }

    pub fn defineProperty(self: Object, context: Context, key: Name, desc: *PropertyDescriptor) ?bool {
        return e.v8__Object__DefineProperty(self, context, key, desc).as_optional();
    }

    pub fn setAccessor(
        self: Object,
        context: Context,
        key: Name,
        getter: AccessorNameGetterCallback,
        setter: ?AccessorNameSetterCallback,
        data: ?Value,
        attr: PropertyAttribute,
    ) ?bool {
        return e.v8__Object__SetAccessor(
            self,
            context,
            key,
            getter,
            setter,
            if (data) |v| v.data.handle else null,
            attr,
        ).as_optional();
    }

    pub fn getIdentityHash(self: Object) c_int {
        return e.v8__Object__GetIdentityHash(self);
    }

    pub fn getCreationContext(self: Object) ?Context {
        return Context.from_opaque(e.v8__Object__GetCreationContext(self));
    }

    pub fn getOwnPropertyNames(self: v8.Object, context: ?v8.Context, filter: u32, key_conversion: i32) ?v8.Array {
        return v8.Array.from_opaque(e.v8__Object__GetOwnPropertyNames(v8.support.rawHandle(self), if (context) |v| v8.support.rawHandle(v) else null, filter, key_conversion));
    }

    pub fn getPropertyNames(self: v8.Object, context: ?v8.Context, mode: i32, property_filter: u32, index_filter: i32, key_conversion: i32) ?v8.Array {
        return v8.Array.from_opaque(e.v8__Object__GetPropertyNames(v8.support.rawHandle(self), if (context) |v| v8.support.rawHandle(v) else null, mode, property_filter, index_filter, key_conversion));
    }

    pub fn has(self: v8.Object, context: v8.Context, key: v8.Value) ?bool {
        return e.v8__Object__Has(self, context, key).as_optional();
    }

    pub fn hasIndex(self: v8.Object, context: v8.Context, index: u32) ?bool {
        return e.v8__Object__HasIndex(self, context, index).as_optional();
    }

    pub fn hasOwnProperty(self: v8.Object, context: v8.Context, key: v8.Name) ?bool {
        return e.v8__Object__HasOwnProperty(self, context, key).as_optional();
    }

    pub fn delete(self: v8.Object, context: v8.Context, key: v8.Value) ?bool {
        return e.v8__Object__Delete(self, context, key).as_optional();
    }

    pub fn deleteIndex(self: v8.Object, context: v8.Context, index: u32) ?bool {
        return e.v8__Object__DeleteIndex(self, context, index).as_optional();
    }

    pub fn internalFieldCount(self: v8.Object) c_int {
        return e.v8__Object__InternalFieldCount(self);
    }

    pub fn getInternalField(self: v8.Object, index: c_int) ?v8.Data {
        return v8.Data.from_opaque(e.v8__Object__GetInternalField(self, index));
    }

    pub fn setIntegrityLevel(self: v8.Object, context: v8.Context, level: i32) ?bool {
        return e.v8__Object__SetIntegrityLevel(self, context, level).as_optional();
    }

    pub fn setInternalField(self: v8.Object, index: c_int, data: v8.Data) void {
        e.v8__Object__SetInternalField(self, index, data);
    }

    pub fn getPrivate(self: v8.Object, context: v8.Context, key: v8.Private) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Object__GetPrivate(self, context, key));
    }

    pub fn setPrivate(self: v8.Object, context: v8.Context, key: v8.Private, value: v8.Value) ?bool {
        return e.v8__Object__SetPrivate(self, context, key, value).as_optional();
    }

    pub fn deletePrivate(self: v8.Object, context: v8.Context, key: v8.Private) ?bool {
        return e.v8__Object__DeletePrivate(self, context, key).as_optional();
    }

    pub fn hasPrivate(self: v8.Object, context: v8.Context, key: v8.Private) ?bool {
        return e.v8__Object__HasPrivate(self, context, key).as_optional();
    }

    pub fn getPropertyAttributes(self: v8.Object, context: v8.Context, key: v8.Value, out: *v8.support.Maybe(v8.PropertyAttribute)) void {
        e.v8__Object__GetPropertyAttributes(self, context, key, out);
    }

    pub fn getOwnPropertyDescriptor(self: v8.Object, context: v8.Context, key: v8.Name) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Object__GetOwnPropertyDescriptor(self, context, key));
    }

    pub fn getRealNamedProperty(self: v8.Object, context: v8.Context, key: v8.Name) ?v8.Value {
        return v8.Value.from_opaque(e.v8__Object__GetRealNamedProperty(self, context, key));
    }

    pub fn hasRealNamedProperty(self: v8.Object, context: v8.Context, key: v8.Name) ?bool {
        return e.v8__Object__HasRealNamedProperty(self, context, key).as_optional();
    }

    pub fn getRealNamedPropertyAttributes(self: v8.Object, context: v8.Context, key: v8.Name, out: *v8.support.Maybe(v8.PropertyAttribute)) void {
        e.v8__Object__GetRealNamedPropertyAttributes(self, context, key, out);
    }

    pub fn previewEntries(self: v8.Object, is_key_value: ?*bool) ?v8.Array {
        return v8.Array.from_opaque(e.v8__Object__PreviewEntries(self, is_key_value));
    }
};
