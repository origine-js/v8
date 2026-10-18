const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const CFunction = v8.CFunction;
const Template = v8.Template;
const FunctionCallback = v8.FunctionCallback;
const Signature = v8.Signature;
const ConstructorBehavior = v8.ConstructorBehavior;
const SideEffectType = v8.SideEffectType;
const Function = v8.Function;
const Context = v8.Context;
const MaybeHandle = v8.MaybeHandle;
const Data = v8.Data;

pub const FunctionTemplate = extern struct {
    pub const Builder = struct {
        data_: ?Data = null,
        signature_: ?Signature = null,
        length_: c_int = 0,
        constructor_behavior_: ConstructorBehavior = .Allow,
        side_effect_type_: SideEffectType = .HasSideEffect,

        pub fn data(self: *@This(), data_: ?Data) *@This() {
            self.data_ = data_;
            return self;
        }

        pub fn signature(self: *@This(), signature_: ?Signature) *@This() {
            self.signature_ = signature_;
            return self;
        }

        pub fn length(self: *@This(), length_: c_int) *@This() {
            self.length_ = length_;
            return self;
        }

        pub fn constructor_behavior(self: *@This(), constructor_behavior_: ConstructorBehavior) *@This() {
            self.constructor_behavior_ = constructor_behavior_;
            return self;
        }

        pub fn side_effect_type(self: *@This(), side_effect_type_: SideEffectType) *@This() {
            self.side_effect_type_ = side_effect_type_;
            return self;
        }

        pub fn build(self: @This(), isolate: Isolate, callback: FunctionCallback, c_functions: []CFunction) FunctionTemplate {
            return .init(isolate, callback, self.data_, self.signature_, self.length_, self.constructor_behavior_, self.side_effect_type_, c_functions);
        }
    };

    template: Template,

    pub fn from_opaque(o: MaybeHandle) @This() {
        return .{
            .template = Template.from_opaque(o).?,
        };
    }

    pub fn init(
        isolate: Isolate,
        callback: FunctionCallback,
        maybe_data: ?Data,
        maybe_signature: ?Signature,
        length_arg: c_int,
        constructor_behavior_arg: ConstructorBehavior,
        side_effect_type_arg: SideEffectType,
        c_functions: []CFunction,
    ) @This() {
        return .from_opaque(e.v8__FunctionTemplate__New(
            isolate.handle,
            callback,
            if (maybe_data) |v| v.handle else null,
            if (maybe_signature) |v| v.handle else null,
            length_arg,
            constructor_behavior_arg,
            side_effect_type_arg,
            @ptrCast(c_functions.ptr),
            c_functions.len,
        ));
    }

    pub fn getFunction(self: @This(), context: Context) ?Function {
        return .from_opaque(e.v8__FunctionTemplate__GetFunction(self, context));
    }

    pub fn setClassName(self: v8.FunctionTemplate, name: v8.String) void {
        e.v8__FunctionTemplate__SetClassName(self, name);
    }

    pub fn inherit(self: v8.FunctionTemplate, parent: v8.FunctionTemplate) void {
        e.v8__FunctionTemplate__Inherit(self, parent);
    }

    pub fn readOnlyPrototype(self: v8.FunctionTemplate) void {
        e.v8__FunctionTemplate__ReadOnlyPrototype(self);
    }

    pub fn removePrototype(self: v8.FunctionTemplate) void {
        e.v8__FunctionTemplate__RemovePrototype(self);
    }

    pub fn prototypeTemplate(self: v8.FunctionTemplate) ?v8.ObjectTemplate {
        return v8.ObjectTemplate.from_opaque(e.v8__FunctionTemplate__PrototypeTemplate(self));
    }

    pub fn instanceTemplate(self: v8.FunctionTemplate) ?v8.ObjectTemplate {
        return v8.ObjectTemplate.from_opaque(e.v8__FunctionTemplate__InstanceTemplate(self));
    }
};
