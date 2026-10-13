const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");

pub const WasmMemoryObject = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn buffer(self: v8.WasmMemoryObject) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.from_opaque(e.v8__WasmMemoryObject__Buffer(self));
    }
};

pub const WasmModuleObject = extern struct {
    object: v8.Object,

    pub fn from_opaque(o: v8.MaybeHandle) ?@This() {
        return .{ .object = v8.Object.from_opaque(o) orelse return null };
    }

    pub fn fromCompiledModule(isolate: v8.Isolate, compiled_module: ?v8.CompiledWasmModule) ?v8.WasmModuleObject {
        return v8.WasmModuleObject.from_opaque(e.v8__WasmModuleObject__FromCompiledModule(isolate.handle, if (compiled_module) |v| v.handle else null));
    }

    pub fn getCompiledModule(self: v8.WasmModuleObject) ?v8.CompiledWasmModule {
        return .{ .handle = e.v8__WasmModuleObject__GetCompiledModule(v8.support.rawHandle(self)) orelse return null };
    }

    pub fn compile(isolate: v8.Isolate, wire_bytes_data: ?[*]u8, length: usize) ?v8.WasmModuleObject {
        return v8.WasmModuleObject.from_opaque(e.v8__WasmModuleObject__Compile(isolate.handle, wire_bytes_data, length));
    }
};

pub const CompiledWasmModule = extern struct {
    pub const Opaque = opaque {};
    handle: *Opaque,

    pub fn getWireBytesRef(self: v8.CompiledWasmModule, length: ?*usize) ?[*]const u8 {
        return e.v8__CompiledWasmModule__GetWireBytesRef(self.handle, length);
    }

    pub fn sourceUrl(self: v8.CompiledWasmModule, length: ?*usize) ?[*]const u8 {
        return e.v8__CompiledWasmModule__SourceUrl(self.handle, length);
    }

    pub fn deinit(self: v8.CompiledWasmModule) void {
        e.v8__CompiledWasmModule__DELETE(self.handle);
    }
};

/// Owns a shared streaming reference. Construct in place and deinit once.
pub const WasmStreaming = extern struct {
    storage: [2]usize,
    pub fn unpack(isolate: v8.Isolate, value: v8.Value, self: *v8.WasmStreaming) void {
        e.v8__WasmStreaming__Unpack(isolate.handle, value, self);
    }

    pub fn deinit(self: *v8.WasmStreaming) void {
        e.v8__WasmStreaming__shared_ptr_DESTRUCT(self);
    }

    pub fn onBytesReceived(self: *v8.WasmStreaming, data: ?[*]const u8, len: usize) void {
        e.v8__WasmStreaming__OnBytesReceived(self, data, len);
    }

    pub fn finish(self: *v8.WasmStreaming) void {
        e.v8__WasmStreaming__Finish(self);
    }

    pub fn abort(self: *v8.WasmStreaming, exception: ?v8.Value) void {
        e.v8__WasmStreaming__Abort(self, if (exception) |v| v8.support.rawHandle(v) else null);
    }

    pub fn setUrl(self: *v8.WasmStreaming, url: ?[*]const u8, len: usize) void {
        e.v8__WasmStreaming__SetUrl(self, url, len);
    }
};
