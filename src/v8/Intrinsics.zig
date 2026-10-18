const e = @import("../generated/externs.gen.zig");
const v8 = @import("../v8.zig");

/// Host-only access to original public builtin method functions, retained by
/// the versioned V8 patch and serialized with each native context.
pub const Intrinsics = struct {
    pub const Prototype = enum {
        array_iterator,
        string_iterator,
        regexp_string_iterator,
        iterator_helper,
        iterator_wrapper,
        intl_segments,
        intl_segment_iterator,
    };

    /// Borrows context on its entered isolate thread through return, with a live
    /// HandleScope. Returns a GC-owned local reference to an original frozen
    /// prototype, valid until that HandleScope ends. Null for disabled entries;
    /// no allocation ownership transfer, getters, or instance construction.
    pub fn getPrototype(context: v8.Context, prototype: Prototype) ?v8.Object {
        const name = @tagName(prototype);
        return .from_opaque(e.v8__Intrinsics__GetPrototype(context, name.ptr, name.len));
    }

    /// Looks up a V8 builtin name (e.g. "ArrayPrototypePush"), without consulting globals
    /// or prototypes. Returns null for unknown, unrecorded, or ambiguous names.
    /// Only methods installed by the patched engine installers are recorded;
    /// this is not a complete ECMAScript intrinsic catalogue or a stub launcher.
    ///
    /// Enter the owning isolate and keep a HandleScope alive. The returned local
    /// is the original frozen function object. Borrows context and name through
    /// return; the GC-owned local result expires with the HandleScope. Call with
    /// an explicit receiver via Function.call. Operations
    /// can still execute guest getters, proxy traps, and other specification hooks.
    /// Keep this lookup private to trusted host code; do not expose it as a guest
    /// capability or use guest-controlled builtin names without your own policy.
    pub fn get(context: v8.Context, name: []const u8) ?v8.Function {
        return .from_opaque(e.v8__Intrinsics__Get(context, name.ptr, name.len));
    }

    /// Returns a new frozen, null-prototype object mapping every available
    /// builtin name to its original function. Omits missing and ambiguous entries.
    /// The engine has already frozen these functions during context creation.
    /// Borrows context through return; the new GC-owned local result expires
    /// with the caller's live HandleScope. Null on failure; consumes no resources.
    /// Same host-only trust boundary and local handle lifetime as get.
    pub fn getAll(context: v8.Context) ?v8.Object {
        return .from_opaque(e.v8__Intrinsics__GetAll(context));
    }

    /// Borrows context through return on its entered isolate thread, with a live
    /// HandleScope. Returns a new GC-owned frozen array containing this realm's
    /// engine-retained frozen intrinsic graph, including hidden prototypes.
    /// Local array and element handles expire with that HandleScope. Null on
    /// failure; empty only for an unfinalized engine seed context. No transfer
    /// or manual release. Keep the inventory private to trusted host code.
    pub fn getObjects(context: v8.Context) ?v8.Array {
        return .from_opaque(e.v8__Intrinsics__GetObjects(context));
    }
};
