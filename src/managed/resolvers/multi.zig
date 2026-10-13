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
    const self: *@This() = @fieldParentPtr("resolver", resolver);
    for (self.resolvers) |r| {
        buf.clearRetainingCapacity();
        return r.on_resolve(specifier, buf, realm) orelse continue;
    }
    return null;
}

const Resolver = @import("../resolver.zig");
const runtime = @import("../runtime.zig");
const std = @import("std");
