resolver: Resolver,

pub fn init() @This() {
    return .{
        .resolver = .{
            .on_resolve = on_resolve,
        },
    };
}

fn on_resolve(resolver: *Resolver, specifier: []const u8, buf: *std.ArrayList(u8), realm: *runtime.JsRealm) ?[]const u8 {
    _ = resolver;
    _ = realm;

    if (!std.mem.startsWith(u8, specifier, "./") and !std.mem.startsWith(u8, specifier, "../")) {
        return null;
    }

    const abs_path = std.fs.path.resolve(buf.allocator, &.{specifier}) catch return null;
    defer buf.allocator.free(abs_path);

    buf.writer().print("file://{s}", .{abs_path}) catch return null;
    return buf.items;
}

const Resolver = @import("../resolver.zig");
const runtime = @import("../runtime.zig");
const std = @import("std");
