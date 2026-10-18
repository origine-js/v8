const binding = @import("../generated/binding.zig");
const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");
const Isolate = v8.Isolate;
const Handle = v8.Handle;
const Data = v8.Data;
const WeakCallbackInfo = v8.WeakCallbackInfo;

pub const Global = extern struct {
    handle: Handle,

    pub fn new(isolate: Isolate, handle: Data) @This() {
        return .{
            .handle = e.v8__Global__New(isolate.handle, handle).?,
        };
    }

    /// A weak global: `callback` runs when the object is about to be collected.
    /// The callback must `deinit` the global (`Weak.handle` is not retained here).
    pub fn newWeak(isolate: Isolate, handle: Data, parameter: ?*anyopaque, callback: WeakCallbackInfo.Callback) @This() {
        return .{
            .handle = e.v8__Global__NewWeak(isolate.handle, handle, parameter, callback).?,
        };
    }

    pub fn deinit(self: @This()) void {
        e.v8__Global__Reset(self.handle);
    }

    /// Promote a persistent handle into the current HandleScope.
    pub fn local(self: @This(), isolate: Isolate) Data {
        const raw = if (binding.opts.is_direct_handle)
            v8.fromRawLocal(@intFromPtr(@as(*v8.Address, @ptrCast(@alignCast(self.handle))).*))
        else
            self.handle;
        return Data.from_opaque(e.v8__Local__New(isolate.handle, Data.from_opaque(raw).?)).?;
    }

    pub fn Of(T: type) type {
        return struct {
            inner: Global,

            pub fn from_global(global: Global) @This() {
                return .{
                    .inner = global,
                };
            }

            pub fn new(isolate: Isolate, data: T) @This() {
                return .{
                    .inner = Global.new(isolate, Data.from_opaque(v8.support.rawHandle(data)).?),
                };
            }

            pub fn deref(self: @This()) T {
                return T.from_opaque(self.inner.local(Isolate.getCurrent()).handle).?;
            }

            pub fn deinit(self: @This()) void {
                self.inner.deinit();
            }
        };
    }
};
