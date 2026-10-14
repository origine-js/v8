const std = @import("std");
const e = @import("../externs.gen.zig");
const v8 = @import("../v8.zig");
const Platform = v8.Platform;
const Isolate = v8.Isolate;

pub const V8 = struct {
    /// Initializes V8 with process-wide strict mode enabled by default.
    /// Registers the lazy embedded ICU provider without expanding the package.
    /// First ICU data use expands it into immutable process-lifetime storage;
    /// configuration failure aborts, data failures propagate via ICU at use.
    /// Retains no caller resources.
    /// Call once, before creating any isolate; V8 freezes flags during initialization.
    pub fn initialize() void {
        setFlagsFromString("--use-strict");
        e.v8__V8__Initialize();
    }

    /// Sets the v8::Platform to use. This should be invoked before V8 is initialized.
    pub fn initializePlatform(platform: Platform) void {
        e.v8__V8__InitializePlatform(platform.handle);
    }

    /// Registers the embedded ICU provider once without expanding any data;
    /// returns configuration success by value and retains no inputs. First ICU
    /// data use expands storage retained until process exit; data errors are
    /// cached and reported through ICU. Do not clean up/reinitialize ICU.
    pub fn initializeICU() bool {
        return e.v8__V8__InitializeICU();
    }

    /// Releases any resources used by v8 and stops any utility thread that may be running.
    pub fn dispose() void {
        _ = e.v8__V8__Dispose();
    }

    /// Clears all references to the v8::Platform. This should be invoked after V8 was disposed.
    pub fn disposePlatform() void {
        e.v8__V8__DisposePlatform();
    }

    pub const EntropySource = *const fn (?[*]u8, usize) callconv(.c) bool;
    pub const FatalErrorCallback = *const fn (location: ?[*]const u8, line: c_int, message: ?[*]const u8) callconv(.c) void;

    pub fn isSandboxEnabled() bool {
        return e.v8__V8__IsSandboxEnabled();
    }

    /// Parses (and removes from `argv`) V8 flags. Exits the process on `--help`.
    pub fn setFlagsFromCommandLine(argc: *c_int, argv: [*]?[*]u8, usage: ?[*:0]const u8) void {
        e.v8__V8__SetFlagsFromCommandLine(argc, argv, usage);
    }

    pub fn setFlagsFromString(flags: []const u8) void {
        e.v8__V8__SetFlagsFromString(flags.ptr, flags.len);
    }

    pub fn setEntropySource(callback: EntropySource) void {
        e.v8__V8__SetEntropySource(callback);
    }

    pub fn getVersion() [:0]const u8 {
        return std.mem.span(@as([*:0]const u8, @ptrCast(e.v8__V8__GetVersion().?)));
    }

    pub fn setFatalErrorHandler(callback: FatalErrorCallback) void {
        e.v8__V8__SetFatalErrorHandler(callback);
    }
};
