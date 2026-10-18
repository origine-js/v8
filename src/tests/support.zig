//! Shared process-lifetime V8 platform for tests; individual tests own their isolates.
const v8 = @import("@v8");

/// Owns the process V8 platform for the test process. Do not copy.
pub const Engine = struct {
    platform: v8.Platform,

    /// Initializes the platform and V8 on the calling thread. Retains nothing from the caller.
    /// Release with deinit after every isolate has died; V8 cannot be reinitialized.
    pub fn init(thread_pool_size: u32) Engine {
        const platform = v8.Platform.initDefault(thread_pool_size, true);
        v8.V8.initializePlatform(platform);
        v8.V8.initialize();
        return .{ .platform = platform };
    }

    /// Consumes this owner on the initializing thread after all isolates are released.
    pub fn deinit(self: *Engine) void {
        v8.V8.dispose();
        v8.V8.disposePlatform();
        self.platform.deinit();
        self.* = undefined;
    }
};

pub var engine: Engine = undefined;
var ready = false;

/// Initializes V8 once on the test runner thread, retaining the engine until
/// process exit. Call before creating isolates; no caller storage is retained.
pub fn ensureV8() void {
    if (ready) return;
    engine = Engine.init(0);
    ready = true;
}
