//! Allocation-free startup diagnostics enabled by V8_STARTUP_TRACE.
pub const StartupTrace = @import("diagnostics/startup.zig");
pub const scope = @import("diagnostics/scope.zig");
