//! Embedding utilities: `const eu = @import("@util");` and `const v = eu.v;`.
//! Call on the entered isolate thread with a live HandleScope. Returned wrappers
//! are local handles, never caller-owned persistent handles; they expire when the
//! enclosing HandleScope closes. Convert to v8.Global to retain a result longer.
const v8 = @import("@v8");

/// Process-lifetime, thread-safe mimalloc allocator; no deinit is required.
/// Callers own its allocations and must release them through this allocator.
pub const alloc = @import("@mimalloc").allocator;

pub const v = struct {
    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn num_f64(isolate: v8.Isolate, value: f64) v8.Number {
        return v8.Number.init(isolate, value);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn num_i32(isolate: v8.Isolate, value: i32) v8.Number {
        return v8.Number.initInt(isolate, value);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn num_u32(isolate: v8.Isolate, value: u32) v8.Number {
        return v8.Number.initUInt(isolate, value);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn bigint_i64(isolate: v8.Isolate, value: i64) v8.BigInt {
        return v8.BigInt.init(isolate, value);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn bigint_u64(isolate: v8.Isolate, value: u64) v8.BigInt {
        return v8.BigInt.initFromUnsigned(isolate, value);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn boolean(isolate: v8.Isolate, value: bool) v8.Boolean {
        return v8.Boolean.init(isolate, value);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn null_value(isolate: v8.Isolate) v8.Primitive {
        return v8.Primitive.initNull(isolate);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn undefined_value(isolate: v8.Isolate) v8.Primitive {
        return v8.Primitive.initUndefined(isolate);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    pub fn object(isolate: v8.Isolate) v8.Object {
        return v8.Object.init(isolate);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// handle valid until that scope closes. Copies scalar inputs; retains no host resources.
    /// Length must be nonnegative; V8 OOM is fatal.
    pub fn array(isolate: v8.Isolate, length: c_int) v8.Array {
        return v8.Array.init(isolate, length);
    }

    /// Borrows elements and their local handles through return; V8 retains the values
    /// in the new array, not the host slice. Requires the entered isolate thread and
    /// a live HandleScope; the local result expires when it closes. Null transfers
    /// no host ownership; input handles remain valid.
    pub fn array_with(isolate: v8.Isolate, elements: []const v8.Value) ?v8.Array {
        return v8.Array.with_elements(isolate, elements);
    }

    /// Borrows immutable input bytes/code units through return; V8 copies the contents.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes. Oversized strings or allocation failure are fatal,
    /// matching the raw constructors; no host ownership transfers.
    pub fn str_utf8(isolate: v8.Isolate, bytes: []const u8) v8.String {
        return v8.String.initUtf8(isolate, bytes);
    }

    /// Borrows immutable input bytes/code units through return; V8 copies the contents.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes. Oversized strings or allocation failure are fatal,
    /// matching the raw constructors; no host ownership transfers.
    /// Returns the canonical string in this isolate's string table.
    pub fn str_utf8_internalized(isolate: v8.Isolate, bytes: []const u8) v8.String {
        return v8.String.initUtf8Internalized(isolate, bytes);
    }

    /// Borrows immutable input bytes/code units through return; V8 copies the contents.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes. Oversized strings or allocation failure are fatal,
    /// matching the raw constructors; no host ownership transfers.
    pub fn str_one_byte(isolate: v8.Isolate, bytes: []const u8) v8.String {
        return v8.String.initOneByte(isolate, bytes);
    }

    /// Borrows immutable input bytes/code units through return; V8 copies the contents.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes. Oversized strings or allocation failure are fatal,
    /// matching the raw constructors; no host ownership transfers.
    /// Returns the canonical string in this isolate's string table.
    pub fn str_one_byte_internalized(isolate: v8.Isolate, bytes: []const u8) v8.String {
        return v8.String.initOneByteInternalized(isolate, bytes);
    }

    /// Borrows immutable input bytes/code units through return; V8 copies the contents.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes. Oversized strings or allocation failure are fatal,
    /// matching the raw constructors; no host ownership transfers.
    pub fn str_two_byte(isolate: v8.Isolate, bytes: []const u16) v8.String {
        return v8.String.initTwoByte(isolate, bytes);
    }

    /// Borrows immutable input bytes/code units through return; V8 copies the contents.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes. Oversized strings or allocation failure are fatal,
    /// matching the raw constructors; no host ownership transfers.
    /// Returns the canonical string in this isolate's string table.
    pub fn str_two_byte_internalized(isolate: v8.Isolate, bytes: []const u16) v8.String {
        return v8.String.initTwoByteInternalized(isolate, bytes);
    }

    /// Borrows immutable backing storage until isolate disposal; never frees it.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes, but V8 may retain its backing storage longer.
    /// Oversized strings or creation failure are fatal, matching the raw constructors.
    pub fn str_external_one_byte(isolate: v8.Isolate, bytes: []const u8) v8.String {
        return v8.String.initOneByteStatic(isolate, bytes);
    }

    /// Borrows immutable backing storage until isolate disposal; never frees it.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes, but V8 may retain its backing storage longer.
    /// Oversized strings or creation failure are fatal, matching the raw constructors.
    /// Internalization may return an existing canonical string, which need not be
    /// external. Keep backing storage alive even when the canonical result differs.
    pub fn str_external_one_byte_internalized(isolate: v8.Isolate, bytes: []const u8) v8.String {
        return v8.String.initOneByteStatic(isolate, bytes).internalize(isolate);
    }

    /// Borrows immutable backing storage until isolate disposal; never frees it.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes, but V8 may retain its backing storage longer.
    /// Oversized strings or creation failure are fatal, matching the raw constructors.
    pub fn str_external_two_byte(isolate: v8.Isolate, bytes: []const u16) v8.String {
        return v8.String.initTwoByteStatic(isolate, bytes);
    }

    /// Borrows immutable backing storage until isolate disposal; never frees it.
    /// Requires the entered isolate thread and a live HandleScope; the local string
    /// expires when it closes, but V8 may retain its backing storage longer.
    /// Oversized strings or creation failure are fatal, matching the raw constructors.
    /// Internalization may return an existing canonical string, which need not be
    /// external. Keep backing storage alive even when the canonical result differs.
    pub fn str_external_two_byte_internalized(isolate: v8.Isolate, bytes: []const u16) v8.String {
        return v8.String.initTwoByteStatic(isolate, bytes).internalize(isolate);
    }

    /// Borrows the description handle through return; V8 retains its string contents.
    /// Requires the entered isolate thread and a live HandleScope; the local result
    /// expires when it closes. Transfers no host ownership.
    pub fn symbol(isolate: v8.Isolate, description: ?v8.String) v8.Symbol {
        return v8.Symbol.init(isolate, description);
    }

    /// Borrows the description handle through return; V8 retains its string contents.
    /// Requires the entered isolate thread and a live HandleScope; the local result
    /// expires when it closes. Transfers no host ownership.
    /// Registry identity and its name may remain retained until isolate disposal.
    pub fn symbol_for(isolate: v8.Isolate, description: v8.String) v8.Symbol {
        return v8.Symbol.@"for"(isolate, description);
    }

    /// Borrows the description handle through return; V8 retains its string contents.
    /// Requires the entered isolate thread and a live HandleScope; the local result
    /// expires when it closes. Transfers no host ownership.
    /// Registry identity and its name may remain retained until isolate disposal.
    pub fn symbol_for_api(isolate: v8.Isolate, description: v8.String) v8.Symbol {
        return v8.Symbol.forApi(isolate, description);
    }

    /// Borrows the description handle through return; V8 retains its string contents.
    /// Requires the entered isolate thread and a live HandleScope; the local result
    /// expires when it closes. Transfers no host ownership.
    pub fn private(isolate: v8.Isolate, description: ?v8.String) v8.Private {
        return v8.Private.init(isolate, description);
    }

    /// Borrows the description handle through return; V8 retains its string contents.
    /// Requires the entered isolate thread and a live HandleScope; the local result
    /// expires when it closes. Transfers no host ownership.
    /// Registry identity and its name may remain retained until isolate disposal.
    pub fn private_for_api(isolate: v8.Isolate, description: v8.String) v8.Private {
        return v8.Private.forApi(isolate, description);
    }

    /// Borrows non-null pointer storage until its last guest use; keeping it live until isolate
    /// disposal is sufficient. V8 stores the pointer and never frees its target.
    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// wrapper valid until that scope closes. Transfers no ownership.
    pub fn external(isolate: v8.Isolate, pointer: *anyopaque) v8.External {
        return v8.External.init(isolate, pointer);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// buffer valid until that scope closes, or null on failure. V8 owns the backing
    /// store through its configured allocator until the last buffer/store reference
    /// is released. Allocator state must outlive those users; no host input is consumed.
    pub fn array_buffer(isolate: v8.Isolate, byte_length: usize) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.newWithByteLength(isolate, byte_length);
    }

    /// Borrows backing_store through return; V8 retains an independent shared reference
    /// on success. Caller still owns and releases its original store. Null transfers
    /// no ownership. Requires the entered isolate thread and a live HandleScope; the
    /// local buffer expires when it closes. Backing allocator/deleter state must live
    /// until the final store reference is released; use a matching shared/unshared store.
    pub fn array_buffer_with(isolate: v8.Isolate, backing_store: *const v8.SharedBackingStore) ?v8.ArrayBuffer {
        return v8.ArrayBuffer.newWithBackingStore(isolate, backing_store);
    }

    /// Requires the entered isolate thread and a live HandleScope; returns a local
    /// buffer valid until that scope closes, or null on failure. V8 owns the backing
    /// store through its configured allocator until the last buffer/store reference
    /// is released. Allocator state must outlive those users; no host input is consumed.
    pub fn shared_array_buffer(isolate: v8.Isolate, byte_length: usize) ?v8.SharedArrayBuffer {
        return v8.SharedArrayBuffer.newWithByteLength(isolate, byte_length);
    }

    /// Borrows backing_store through return; V8 retains an independent shared reference
    /// on success. Caller still owns and releases its original store. Null transfers
    /// no ownership. Requires the entered isolate thread and a live HandleScope; the
    /// local buffer expires when it closes. Backing allocator/deleter state must live
    /// until the final store reference is released; use a matching shared/unshared store.
    pub fn shared_array_buffer_with(isolate: v8.Isolate, backing_store: *const v8.SharedBackingStore) ?v8.SharedArrayBuffer {
        return v8.SharedArrayBuffer.newWithBackingStore(isolate, backing_store);
    }

    /// Borrows the entered context through return on its isolate thread with a live
    /// HandleScope. Returns a local resolver valid until that scope closes, or null
    /// on failure. V8 owns its promise; no host resources or persistent handles transfer.
    pub fn promise_resolver(context: v8.Context) ?v8.Promise.Resolver {
        return v8.Promise.Resolver.init(context);
    }

    /// Borrows the message handle through return; the V8 exception retains its text.
    /// Requires the message's entered isolate thread and a live HandleScope. Returns
    /// a local exception value valid until that scope closes, or null on failure.
    /// Constructs without throwing; transfers no host ownership.
    pub fn err(message: v8.String) ?v8.Value {
        return v8.Exception.@"error"(message);
    }

    /// Borrows the message handle through return; the V8 exception retains its text.
    /// Requires the message's entered isolate thread and a live HandleScope. Returns
    /// a local exception value valid until that scope closes, or null on failure.
    /// Constructs without throwing; transfers no host ownership.
    pub fn type_error(message: v8.String) ?v8.Value {
        return v8.Exception.typeError(message);
    }

    /// Borrows the message handle through return; the V8 exception retains its text.
    /// Requires the message's entered isolate thread and a live HandleScope. Returns
    /// a local exception value valid until that scope closes, or null on failure.
    /// Constructs without throwing; transfers no host ownership.
    pub fn range_error(message: v8.String) ?v8.Value {
        return v8.Exception.rangeError(message);
    }

    /// Borrows the message handle through return; the V8 exception retains its text.
    /// Requires the message's entered isolate thread and a live HandleScope. Returns
    /// a local exception value valid until that scope closes, or null on failure.
    /// Constructs without throwing; transfers no host ownership.
    pub fn reference_error(message: v8.String) ?v8.Value {
        return v8.Exception.referenceError(message);
    }

    /// Borrows the message handle through return; the V8 exception retains its text.
    /// Requires the message's entered isolate thread and a live HandleScope. Returns
    /// a local exception value valid until that scope closes, or null on failure.
    /// Constructs without throwing; transfers no host ownership.
    pub fn syntax_error(message: v8.String) ?v8.Value {
        return v8.Exception.syntaxError(message);
    }
};
