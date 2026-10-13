pub const OnResolve = fn (*@This(), specifier: []const u8, buf: *std.ArrayList(u8), realm: *runtime.JsRealm) ?[]const u8;

on_resolve: *const OnResolve,

pub fn resolve(self: *@This(), specifier: []const u8, buf: *std.ArrayList(u8), realm: *runtime.JsRealm) ?[]const u8 {
    return self.on_resolve(self, specifier, buf, realm);
}

const std = @import("std");
const runtime = @import("./runtime.zig");
