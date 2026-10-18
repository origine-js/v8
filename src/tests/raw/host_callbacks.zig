const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const support = @import("support.zig");
const Env = support.Env;
const withEnv = support.withEnv;

var import_attribute_count: c_int = -1;

/// Borrows callback handles through return in the entered context and live
/// HandleScope. Returns a local rejected promise; records only a scalar count.
fn cbHostImport(
    ctx: v8.Context,
    _: v8.Data,
    _: v8.Value,
    specifier: v8.String,
    attributes: v8.FixedArray,
) callconv(.c) v8.MaybeHandle {
    import_attribute_count = attributes.len();
    const resolver = v8.Promise.Resolver.init(ctx).?;
    _ = resolver.reject(ctx, specifier.name.primitive.value);
    return resolver.getPromise().object.value.data.handle;
}

/// Borrows local callback handles until return; retains no resources.
fn cbImportMeta(_: v8.Context, _: v8.Module, _: v8.Object) callconv(.c) void {}

test "Isolate: dynamic import() reaches the host callback" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; local handles expire with
        /// its HandleScope. Test-owned persistent handles/host buffers are released on
        /// success and failure; no resources escape to the caller.
        fn run(env: *Env) !void {
            import_attribute_count = -1;
            env.isolate.setMicrotasksPolicy(.Explicit);
            env.isolate.setHostInitializeImportMetaObjectCallback(cbImportMeta);
            env.isolate.setHostImportModuleDynamicallyCallback(cbHostImport);

            _ = env.eval("globalThis.err = null; import('virtual:thing').catch(e => { err = e; })");
            env.isolate.performMicrotasksCheckpoint();
            try env.expectEval("err", "virtual:thing");
            try t.expectEqual(@as(c_int, 0), import_attribute_count);
        }
    }.run);
}
