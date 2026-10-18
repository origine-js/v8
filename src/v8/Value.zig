const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const support = v8.support;
const Context = v8.Context;
const MaybeHandle = v8.MaybeHandle;
const Data = v8.Data;
const String = v8.String;
const Isolate = v8.Isolate;
const Object = v8.Object;
const Number = v8.Number;
const Integer = v8.Integer;
const Int32 = v8.Int32;
const Uint32 = v8.Uint32;
const BigInt = v8.BigInt;
const Boolean = v8.Boolean;

pub const Value = extern struct {
    data: Data,

    pub fn from_opaque(o: MaybeHandle) ?@This() {
        return .{
            .data = Data.from_opaque(o) orelse return null,
        };
    }

    pub fn toString(self: @This(), context: Context) ?String {
        return String.from_opaque(e.v8__Value__ToString(self, context));
    }

    pub fn isNumber(self: @This()) bool {
        return e.v8__Value__IsNumber(self);
    }

    pub fn u32Value(self: @This(), context: Context) ?u32 {
        var out: support.Maybe(u32) = undefined;
        e.v8__Value__Uint32Value(self, context, &out);
        return out.as_optional();
    }

    pub fn i32Value(self: @This(), context: Context) ?i32 {
        var out: support.Maybe(i32) = undefined;
        e.v8__Value__Int32Value(self, context, &out);
        return out.as_optional();
    }

    pub fn isUndefined(self: @This()) bool {
        return e.v8__Value__IsUndefined(self);
    }

    pub fn isNull(self: @This()) bool {
        return e.v8__Value__IsNull(self);
    }

    pub fn isNullOrUndefined(self: @This()) bool {
        return e.v8__Value__IsNullOrUndefined(self);
    }

    pub fn isTrue(self: @This()) bool {
        return e.v8__Value__IsTrue(self);
    }

    pub fn isFalse(self: @This()) bool {
        return e.v8__Value__IsFalse(self);
    }

    pub fn isName(self: @This()) bool {
        return e.v8__Value__IsName(self);
    }

    pub fn isString(self: @This()) bool {
        return e.v8__Value__IsString(self);
    }

    pub fn isSymbol(self: @This()) bool {
        return e.v8__Value__IsSymbol(self);
    }

    pub fn isFunction(self: @This()) bool {
        return e.v8__Value__IsFunction(self);
    }

    pub fn isArray(self: @This()) bool {
        return e.v8__Value__IsArray(self);
    }

    pub fn isObject(self: @This()) bool {
        return e.v8__Value__IsObject(self);
    }

    pub fn isBigInt(self: @This()) bool {
        return e.v8__Value__IsBigInt(self);
    }

    pub fn isBoolean(self: @This()) bool {
        return e.v8__Value__IsBoolean(self);
    }

    pub fn isExternal(self: @This()) bool {
        return e.v8__Value__IsExternal(self);
    }

    pub fn isInt32(self: @This()) bool {
        return e.v8__Value__IsInt32(self);
    }

    pub fn isUint32(self: @This()) bool {
        return e.v8__Value__IsUint32(self);
    }

    pub fn isDate(self: @This()) bool {
        return e.v8__Value__IsDate(self);
    }

    pub fn isArgumentsObject(self: @This()) bool {
        return e.v8__Value__IsArgumentsObject(self);
    }

    pub fn isBigIntObject(self: @This()) bool {
        return e.v8__Value__IsBigIntObject(self);
    }

    pub fn isBooleanObject(self: @This()) bool {
        return e.v8__Value__IsBooleanObject(self);
    }

    pub fn isNumberObject(self: @This()) bool {
        return e.v8__Value__IsNumberObject(self);
    }

    pub fn isStringObject(self: @This()) bool {
        return e.v8__Value__IsStringObject(self);
    }

    pub fn isSymbolObject(self: @This()) bool {
        return e.v8__Value__IsSymbolObject(self);
    }

    pub fn isNativeError(self: @This()) bool {
        return e.v8__Value__IsNativeError(self);
    }

    pub fn isRegExp(self: @This()) bool {
        return e.v8__Value__IsRegExp(self);
    }

    pub fn isAsyncFunction(self: @This()) bool {
        return e.v8__Value__IsAsyncFunction(self);
    }

    pub fn isGeneratorFunction(self: @This()) bool {
        return e.v8__Value__IsGeneratorFunction(self);
    }

    pub fn isGeneratorObject(self: @This()) bool {
        return e.v8__Value__IsGeneratorObject(self);
    }

    pub fn isPromise(self: @This()) bool {
        return e.v8__Value__IsPromise(self);
    }

    pub fn isMap(self: @This()) bool {
        return e.v8__Value__IsMap(self);
    }

    pub fn isSet(self: @This()) bool {
        return e.v8__Value__IsSet(self);
    }

    pub fn isMapIterator(self: @This()) bool {
        return e.v8__Value__IsMapIterator(self);
    }

    pub fn isSetIterator(self: @This()) bool {
        return e.v8__Value__IsSetIterator(self);
    }

    pub fn isSetGeneratorObject(self: @This()) bool {
        return e.v8__Value__IsSetGeneratorObject(self);
    }

    pub fn isWeakMap(self: @This()) bool {
        return e.v8__Value__IsWeakMap(self);
    }

    pub fn isWeakSet(self: @This()) bool {
        return e.v8__Value__IsWeakSet(self);
    }

    pub fn isArrayBuffer(self: @This()) bool {
        return e.v8__Value__IsArrayBuffer(self);
    }

    pub fn isArrayBufferView(self: @This()) bool {
        return e.v8__Value__IsArrayBufferView(self);
    }

    pub fn isTypedArray(self: @This()) bool {
        return e.v8__Value__IsTypedArray(self);
    }

    pub fn isUint8Array(self: @This()) bool {
        return e.v8__Value__IsUint8Array(self);
    }

    pub fn isUint8ClampedArray(self: @This()) bool {
        return e.v8__Value__IsUint8ClampedArray(self);
    }

    pub fn isInt8Array(self: @This()) bool {
        return e.v8__Value__IsInt8Array(self);
    }

    pub fn isUint16Array(self: @This()) bool {
        return e.v8__Value__IsUint16Array(self);
    }

    pub fn isInt16Array(self: @This()) bool {
        return e.v8__Value__IsInt16Array(self);
    }

    pub fn isUint32Array(self: @This()) bool {
        return e.v8__Value__IsUint32Array(self);
    }

    pub fn isInt32Array(self: @This()) bool {
        return e.v8__Value__IsInt32Array(self);
    }

    pub fn isFloat16Array(self: @This()) bool {
        return e.v8__Value__IsFloat16Array(self);
    }

    pub fn isFloat32Array(self: @This()) bool {
        return e.v8__Value__IsFloat32Array(self);
    }

    pub fn isFloat64Array(self: @This()) bool {
        return e.v8__Value__IsFloat64Array(self);
    }

    pub fn isBigInt64Array(self: @This()) bool {
        return e.v8__Value__IsBigInt64Array(self);
    }

    pub fn isBigUint64Array(self: @This()) bool {
        return e.v8__Value__IsBigUint64Array(self);
    }

    pub fn isDataView(self: @This()) bool {
        return e.v8__Value__IsDataView(self);
    }

    pub fn isSharedArrayBuffer(self: @This()) bool {
        return e.v8__Value__IsSharedArrayBuffer(self);
    }

    pub fn isProxy(self: @This()) bool {
        return e.v8__Value__IsProxy(self);
    }

    pub fn isWasmModuleObject(self: @This()) bool {
        return e.v8__Value__IsWasmModuleObject(self);
    }

    pub fn isWasmMemoryObject(self: @This()) bool {
        return e.v8__Value__IsWasmMemoryObject(self);
    }

    pub fn isModuleNamespaceObject(self: @This()) bool {
        return e.v8__Value__IsModuleNamespaceObject(self);
    }

    pub fn strictEquals(self: @This(), that: @This()) bool {
        return e.v8__Value__StrictEquals(self, that);
    }

    pub fn sameValue(self: @This(), that: @This()) bool {
        return e.v8__Value__SameValue(self, that);
    }

    pub fn toUint32(self: @This(), context: Context) ?Uint32 {
        return Uint32.from_opaque(e.v8__Value__ToUint32(self, context));
    }

    pub fn toInt32(self: @This(), context: Context) ?Int32 {
        return Int32.from_opaque(e.v8__Value__ToInt32(self, context));
    }

    pub fn toInteger(self: @This(), context: Context) ?Integer {
        return Integer.from_opaque(e.v8__Value__ToInteger(self, context));
    }

    pub fn toBigInt(self: @This(), context: Context) ?BigInt {
        return BigInt.from_opaque(e.v8__Value__ToBigInt(self, context));
    }

    pub fn toDetailString(self: @This(), context: Context) ?String {
        return String.from_opaque(e.v8__Value__ToDetailString(self, context));
    }

    pub fn toNumber(self: @This(), context: Context) ?Number {
        return Number.from_opaque(e.v8__Value__ToNumber(self, context));
    }

    pub fn toObject(self: @This(), context: Context) ?Object {
        return Object.from_opaque(e.v8__Value__ToObject(self, context));
    }

    pub fn toBoolean(self: @This(), isolate: Isolate) Boolean {
        return Boolean.from_opaque(e.v8__Value__ToBoolean(self, isolate.handle)).?;
    }

    pub fn instanceOf(self: @This(), context: Context, object: Object) ?bool {
        var out: support.Maybe(bool) = undefined;
        e.v8__Value__InstanceOf(self, context, object, &out);
        return out.as_optional();
    }

    pub fn numberValue(self: @This(), context: Context) ?f64 {
        var out: support.Maybe(f64) = undefined;
        e.v8__Value__NumberValue(self, context, &out);
        return out.as_optional();
    }

    pub fn integerValue(self: @This(), context: Context) ?i64 {
        var out: support.Maybe(i64) = undefined;
        e.v8__Value__IntegerValue(self, context, &out);
        return out.as_optional();
    }

    pub fn booleanValue(self: @This(), isolate: Isolate) bool {
        return e.v8__Value__BooleanValue(self, isolate.handle);
    }

    pub fn typeOf(self: @This(), isolate: Isolate) String {
        return String.from_opaque(e.v8__Value__TypeOf(self, isolate.handle)).?;
    }

    pub fn getHash(self: @This()) u32 {
        return e.v8__Value__GetHash(self);
    }
};
