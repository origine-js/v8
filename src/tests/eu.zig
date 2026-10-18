const std = @import("std");
const t = std.testing;
const v8 = @import("@v8");
const eu = @import("@util");
const v = eu.v;
const Env = @import("raw/support.zig").Env;
const withEnv = @import("raw/support.zig").withEnv;
const external_two_bytes: [64]u16 = @splat(0x4e16);

test "eu: typed scalar constructors preserve numeric boundaries and pointer identity" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; all local handles expire
        /// with its HandleScope. The external pointer is used only during this call.
        fn run(env: *Env) !void {
            std.testing.refAllDecls(eu);
            std.testing.refAllDecls(v);
            const signed: v8.Number = v.num_i32(env.isolate, std.math.minInt(i32));
            const unsigned: v8.Number = v.num_u32(env.isolate, std.math.maxInt(u32));
            try t.expectEqual(@as(f64, -2147483648), signed.Value());
            try t.expectEqual(@as(f64, 4294967295), unsigned.Value());
            try t.expectEqual(@as(f64, 0.25), v.num_f64(env.isolate, 0.25).Value());
            try t.expect(std.math.isNan(v.num_f64(env.isolate, std.math.nan(f64)).Value()));
            try t.expectEqual(std.math.minInt(i64), v.bigint_i64(env.isolate, std.math.minInt(i64)).int64Value(null));
            try t.expectEqual(std.math.maxInt(u64), v.bigint_u64(env.isolate, std.math.maxInt(u64)).uint64Value(null));
            const boolean: v8.Boolean = v.boolean(env.isolate, true);
            try t.expect(boolean.primitive.value.isTrue());
            try t.expect(v.boolean(env.isolate, false).primitive.value.isFalse());
            try t.expect(v.null_value(env.isolate).value.isNull());
            try t.expect(v.undefined_value(env.isolate).value.isUndefined());
            try t.expect(v.object(env.isolate).value.isObject());
            var host: u32 = 7;
            const external: v8.External = v.external(env.isolate, &host);
            try t.expectEqual(@as(?*anyopaque, &host), external.pointer());
        }
    }.run);
}

test "eu: copied strings decode encodings and internalized pairs enter the string table" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; source arrays are local
        /// and copied by V8. Local handles expire with the fixture's HandleScope.
        fn run(env: *Env) !void {
            var utf8 = [_]u8{ 0xc3, 0xa9, 0, 'x' };
            var latin1 = [_]u8{ 0xe9, 0, 'x' };
            var utf16 = [_]u16{ 0xe9, 0, 'x' };
            const strings = [_]v8.String{
                v.str_utf8(env.isolate, &utf8),
                v.str_one_byte(env.isolate, &latin1),
                v.str_two_byte(env.isolate, &utf16),
            };
            const canonical = [_]v8.String{
                v.str_utf8_internalized(env.isolate, &utf8),
                v.str_one_byte_internalized(env.isolate, &latin1),
                v.str_two_byte_internalized(env.isolate, &utf16),
            };
            @memset(&utf8, 'z');
            @memset(&latin1, 'z');
            @memset(&utf16, 'z');
            for (strings) |string| {
                try t.expectEqual(@as(c_int, 3), string.len());
                const bytes = try env.utf8(string.name.primitive.value);
                defer t.allocator.free(bytes);
                try t.expectEqualStrings("é\x00x", bytes);
            }
            for (canonical) |string| {
                try t.expect(string.isInStringTable(env.isolate));
                try t.expect(string.name.primitive.value.data.eq(canonical[0].name.primitive.value.data));
            }
            const astral = v.str_two_byte(env.isolate, &.{ 0xd83d, 0xde00 });
            const bytes = try env.utf8(astral.name.primitive.value);
            defer t.allocator.free(bytes);
            try t.expectEqualStrings("😀", bytes);
            try t.expectEqual(@as(c_int, 0), v.str_utf8(env.isolate, "").len());
            try t.expect(v.str_one_byte_internalized(env.isolate, "").isInStringTable(env.isolate));
        }
    }.run);
}

test "eu: external string pairs borrow static storage and canonicalize correctly" {
    try withEnv(struct {
        /// Borrows the entered fixture through return. External backing arrays
        /// have static lifetime and outlive isolate disposal; retains no host owner.
        fn run(env: *Env) !void {
            const one = "external eu one-byte string with enough characters";
            const two = &external_two_bytes;
            const one_string: v8.String = v.str_external_one_byte(env.isolate, one);
            const two_string: v8.String = v.str_external_two_byte(env.isolate, two);
            try t.expect(one_string.isExternalOneByte());
            try t.expect(two_string.isExternalTwoByte());
            {
                var view: v8.String.ValueView = undefined;
                view.init(env.isolate, one_string);
                defer view.deinit();
                try t.expectEqual(@intFromPtr(one.ptr), @intFromPtr(view.bytes().?.ptr));
            }
            {
                var view: v8.String.ValueView = undefined;
                view.init(env.isolate, two_string);
                defer view.deinit();
                try t.expectEqual(@intFromPtr(two.ptr), @intFromPtr(view.words().?.ptr));
            }
            const internal_one = v.str_external_one_byte_internalized(env.isolate, one);
            const internal_two = v.str_external_two_byte_internalized(env.isolate, two);
            try t.expect(internal_one.isInStringTable(env.isolate));
            try t.expect(internal_two.isInStringTable(env.isolate));
            try t.expect(internal_one.name.primitive.value.data.eq(v.str_one_byte_internalized(env.isolate, one).name.primitive.value.data));
            try t.expect(internal_two.name.primitive.value.data.eq(v.str_two_byte_internalized(env.isolate, two).name.primitive.value.data));
        }
    }.run);
}

test "eu: arrays retain element values independently of the input slice" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; V8 copies the input slice
        /// of handles into its array. All results expire with the fixture HandleScope.
        fn run(env: *Env) !void {
            try t.expectEqual(@as(u32, 3), v.array(env.isolate, 3).len());
            var elements = [_]v8.Value{
                v.num_i32(env.isolate, 42).numeric.primitive.value,
                v.str_utf8(env.isolate, "hello").name.primitive.value,
            };
            const array: v8.Array = v.array_with(env.isolate, &elements).?;
            @memset(&elements, v.undefined_value(env.isolate).value);
            env.setGlobal("array", array.object.value);
            try env.expectEval("JSON.stringify(array)", "[42,\"hello\"]");
            try t.expectEqual(@as(u32, 0), v.array_with(env.isolate, &.{}).?.len());
        }
    }.run);
}

test "eu: symbol and private constructors preserve unique and registry identities" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; isolate registries retain
        /// names until disposal. All returned wrappers are local, not persistent.
        fn run(env: *Env) !void {
            const name = v.str_utf8(env.isolate, "eu name");
            const a: v8.Symbol = v.symbol(env.isolate, name);
            const b = v.symbol(env.isolate, name);
            try t.expect(!a.name.primitive.value.strictEquals(b.name.primitive.value));
            try t.expect(v.symbol(env.isolate, null).description(env.isolate).isUndefined());
            try t.expect(v.symbol_for(env.isolate, name).name.primitive.value.strictEquals(v.symbol_for(env.isolate, name).name.primitive.value));
            try t.expect(v.symbol_for_api(env.isolate, name).name.primitive.value.strictEquals(v.symbol_for_api(env.isolate, name).name.primitive.value));
            try t.expect(!v.symbol_for(env.isolate, name).name.primitive.value.strictEquals(v.symbol_for_api(env.isolate, name).name.primitive.value));
            const key: v8.Private = v.private(env.isolate, name);
            try t.expect(!key.data.eq(v.private(env.isolate, name).data));
            try t.expect(v.private(env.isolate, null).name().isUndefined());
            try t.expect(v.private_for_api(env.isolate, name).data.eq(v.private_for_api(env.isolate, name).data));
        }
    }.run);
}

test "eu: array buffers share stores and promise resolvers settle typed values" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; releases caller-owned
        /// shared-store references on success/error. V8 owns buffer allocations
        /// until isolate teardown; local buffers/resolver expire with HandleScope.
        fn run(env: *Env) !void {
            const buffer: v8.ArrayBuffer = v.array_buffer(env.isolate, 16).?;
            var store = buffer.getBackingStore();
            defer store.deinit();
            const alias = v.array_buffer_with(env.isolate, &store).?;
            try t.expectEqual(@as(usize, 16), alias.byteLength());
            try t.expectEqual(buffer.data(), alias.data());
            const bytes: [*]u8 = @ptrCast(buffer.data().?);
            try t.expectEqualSlices(u8, &@as([16]u8, @splat(0)), bytes[0..16]);
            bytes[3] = 42;
            env.setGlobal("buffer", alias.object.value);
            try env.expectEval("new Uint8Array(buffer)[3]", "42");
            try t.expectEqual(@as(usize, 0), v.array_buffer(env.isolate, 0).?.byteLength());
            const shared: v8.SharedArrayBuffer = v.shared_array_buffer(env.isolate, 32).?;
            var shared_store = shared.getBackingStore();
            defer shared_store.deinit();
            try t.expectEqual(@as(usize, 32), v.shared_array_buffer_with(env.isolate, &shared_store).?.byteLength());
            const resolver: v8.Promise.Resolver = v.promise_resolver(env.context).?;
            try t.expectEqual(v8.Promise.PromiseState.Pending, resolver.getPromise().state());
            try t.expect(resolver.resolve(env.context, v.num_i32(env.isolate, 7).numeric.primitive.value).?);
            try t.expectEqual(v8.Promise.PromiseState.Fulfilled, resolver.getPromise().state());
            try t.expectEqual(@as(?i32, 7), resolver.getPromise().result().i32Value(env.context));
        }
    }.run);
}

test "eu: exception constructors produce errors without throwing" {
    try withEnv(struct {
        /// Borrows the entered fixture through return; temporary UTF-8 buffers
        /// and TryCatch are released on success/error. Local errors expire with
        /// the fixture HandleScope; no persistent handles escape.
        fn run(env: *Env) !void {
            var tc_scope: v8.TryCatch = undefined;
            tc_scope.init(env.isolate);
            defer tc_scope.deinit();
            const message = v.str_utf8(env.isolate, "eu failure");
            const errors = [_]v8.Value{
                v.err(message).?,             v.type_error(message).?,   v.range_error(message).?,
                v.reference_error(message).?, v.syntax_error(message).?,
            };
            for (errors, [_][]const u8{ "Error", "TypeError", "RangeError", "ReferenceError", "SyntaxError" }) |err, name| {
                try t.expect(err.isNativeError());
                const bytes = try env.utf8(err);
                defer t.allocator.free(bytes);
                try t.expect(std.mem.startsWith(u8, bytes, name));
                try t.expect(std.mem.endsWith(u8, bytes, ": eu failure"));
            }
            try t.expect(!tc_scope.hasCaught());
        }
    }.run);
}
