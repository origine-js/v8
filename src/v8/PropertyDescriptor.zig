const binding = @import("../generated/binding.zig");
const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Value = v8.Value;

// https://github.com/denoland/rusty_v8/blob/4d9f92762600fd3475a5632005ecf3721514b8d4/src/property_attribute.rs#L5
pub const PropertyDescriptor = extern struct {
    pub const Opaque = [binding.sizes.PropertyDescriptor]u8;
    inner: Opaque align(@alignOf(usize)),

    pub fn init() PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        e.v8__PropertyDescriptor__CONSTRUCT(&self.inner);
        return self;
    }

    pub fn initValue(value_arg: Value, writable_arg: ?bool) PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        if (writable_arg) |w| {
            e.v8__PropertyDescriptor__CONSTRUCT__Value_Writable(&self.inner, value_arg, w);
        } else {
            e.v8__PropertyDescriptor__CONSTRUCT__Value(&self.inner, value_arg);
        }
        return self;
    }

    pub fn initGetSet(get_arg: Value, set_arg: Value) PropertyDescriptor {
        var self: PropertyDescriptor = undefined;
        e.v8__PropertyDescriptor__CONSTRUCT__Get_Set(&self.inner, get_arg, set_arg);
        return self;
    }

    pub fn deinit(self: *PropertyDescriptor) void {
        e.v8__PropertyDescriptor__DESTRUCT(&self.inner);
    }

    pub fn configurable(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__configurable(&self.inner);
    }

    pub fn enumerable(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__enumerable(&self.inner);
    }

    pub fn writable(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__writable(&self.inner);
    }

    pub fn value(self: *const v8.PropertyDescriptor) ?v8.Value {
        return v8.Value.from_opaque(e.v8__PropertyDescriptor__value(&self.inner));
    }

    pub fn get(self: *const v8.PropertyDescriptor) ?v8.Value {
        return v8.Value.from_opaque(e.v8__PropertyDescriptor__get(&self.inner));
    }

    pub fn set(self: *const v8.PropertyDescriptor) ?v8.Value {
        return v8.Value.from_opaque(e.v8__PropertyDescriptor__set(&self.inner));
    }

    pub fn hasConfigurable(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__has_configurable(&self.inner);
    }

    pub fn hasEnumerable(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__has_enumerable(&self.inner);
    }

    pub fn hasWritable(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__has_writable(&self.inner);
    }

    pub fn hasValue(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__has_value(&self.inner);
    }

    pub fn hasGet(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__has_get(&self.inner);
    }

    pub fn hasSet(self: *const v8.PropertyDescriptor) bool {
        return e.v8__PropertyDescriptor__has_set(&self.inner);
    }

    pub fn setEnumerable(self: *v8.PropertyDescriptor, enumurable: bool) void {
        e.v8__PropertyDescriptor__set_enumerable(&self.inner, enumurable);
    }

    pub fn setConfigurable(self: *v8.PropertyDescriptor, configurable_arg: bool) void {
        e.v8__PropertyDescriptor__set_configurable(&self.inner, configurable_arg);
    }
};
