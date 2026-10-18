const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

pub const WasmMemoryObject = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn buffer(self: WasmMemoryObject) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.from_opaque(e.v8__WasmMemoryObject__Buffer(self));
    }
};

pub const WasmModuleObject = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn fromCompiledModule(isolate: v8.Isolate, compiled_module: ?CompiledWasmModule) ?WasmModuleObject {
        return WasmModuleObject.from_opaque(e.v8__WasmModuleObject__FromCompiledModule(isolate.handle, if (compiled_module) |v| @ptrCast(@alignCast(v.handle)) else null));
    }

    pub fn getCompiledModule(self: WasmModuleObject) ?CompiledWasmModule {
        return .{ .handle = @ptrCast(@alignCast(e.v8__WasmModuleObject__GetCompiledModule(@ptrCast(@alignCast(v8.support.rawHandle(self)))) orelse return null)) };
    }

    pub fn compile(isolate: v8.Isolate, wire_bytes_data: ?[*]u8, length: usize) ?WasmModuleObject {
        return WasmModuleObject.from_opaque(e.v8__WasmModuleObject__Compile(isolate.handle, wire_bytes_data, length));
    }
};

pub const CompiledWasmModule = extern struct {
    pub const Opaque = opaque {};
    handle: *Opaque,

    pub fn getWireBytesRef(self: CompiledWasmModule, length: ?*usize) ?[*]const u8 {
        return e.v8__CompiledWasmModule__GetWireBytesRef(@ptrCast(@alignCast(self.handle)), length);
    }

    pub fn sourceUrl(self: CompiledWasmModule, length: ?*usize) ?[*]const u8 {
        return e.v8__CompiledWasmModule__SourceUrl(@ptrCast(@alignCast(self.handle)), length);
    }

    pub fn deinit(self: CompiledWasmModule) void {
        e.v8__CompiledWasmModule__DELETE(@ptrCast(@alignCast(self.handle)));
    }
};

/// Owns a shared streaming reference. Construct in place and deinit once.
pub const WasmStreaming = extern struct {
    storage: [2]usize,
    pub fn unpack(isolate: v8.Isolate, value: v8.Value, self: *WasmStreaming) void {
        e.v8__WasmStreaming__Unpack(isolate.handle, value, self);
    }

    pub fn deinit(self: *WasmStreaming) void {
        e.v8__WasmStreaming__shared_ptr_DESTRUCT(self);
    }

    pub fn onBytesReceived(self: *WasmStreaming, data: ?[*]const u8, len: usize) void {
        e.v8__WasmStreaming__OnBytesReceived(self, data, len);
    }

    pub fn finish(self: *WasmStreaming) void {
        e.v8__WasmStreaming__Finish(self);
    }

    pub fn abort(self: *WasmStreaming, exception: ?v8.Value) void {
        e.v8__WasmStreaming__Abort(self, if (exception) |v| v8.support.rawHandle(v) else null);
    }

    pub fn setUrl(self: *WasmStreaming, url: ?[*]const u8, len: usize) void {
        e.v8__WasmStreaming__SetUrl(self, url, len);
    }
};
