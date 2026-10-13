resolvers: []*Resolver,
resolver: Resolver,

pub fn init(resolvers: []*Resolver) @This() {
    return .{
        .resolvers = resolvers,
        .resolver = .{
            .on_resolve = on_resolve,
        },
    };
}

fn on_resolve(resolver: *Resolver, specifier: []const u8, buf: *std.ArrayList(u8), realm: *runtime.JsRealm) ?[]const u8 {
    _ = resolver;
    _ = specifier;
    _ = buf;
    _ = realm;
    return null;
}

const Resolver = @import("../resolver.zig");
const runtime = @import("../runtime.zig");
const std = @import("std");
