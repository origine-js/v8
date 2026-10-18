# Original builtin references

`v8.Intrinsics.get(context, "ArrayPrototypePush")` returns the original public
method function from that context. It does not consult JavaScript globals or
prototype properties, invoke getters, or create a replacement function.

`v8.Intrinsics.getAll(context)` returns a new frozen, null-prototype object
mapping all available builtin names to their original functions. Unknown,
unrecorded, and ambiguous entries are omitted. The engine freezes the original
function objects before returning the context. The result has the same host-only trust
boundary and local handle lifetime as `get`.

```zig
// The owning isolate must be entered and a HandleScope must be alive.
const push = v8.Intrinsics.get(context, "ArrayPrototypePush") orelse
    return error.IntrinsicUnavailable;
const result = push.call(context, array.object.value, &.{value}) orelse
    return error.JavaScriptException;
```

There is no caller-side primordial inventory or prototype traversal. The V8
bootstrap method installers retain functions automatically, in a private
`FixedArray` owned by the native context. Normal garbage collection traces the
table, and snapshots serialize it with the context. Builtin properties reject
replacement and deletion. Each context retains its
own functions; no foreign realm is used.

`v8.Intrinsics.getObjects(context)` returns a new frozen array of the complete
engine-retained intrinsic object graph, including hidden iterator, generator,
Segments, and SegmentIterator prototypes. Elements are the original frozen
objects from this context. This host-only inventory lets the managed export
hardener recognize genuine intrinsics without trusting `Object.isFrozen` or
constructing instances. The array and its element handles have the caller's
local HandleScope lifetime; V8 owns their storage.

`v8.Intrinsics.getPrototype(context, .intl_segments)` and
`.intl_segment_iterator` read hidden Intl prototypes directly. The other enum
entries provide array, string, RegExp string, helper, and wrapper iterator
prototypes for managed export validation. These lookups use the same host-only
boundary and local handle lifetime; unavailable entries return null.

## Engine finalization

The ordered hardening patches install immutable builtin properties and complete
the core, iteration, Intl, and Temporal subsystems after their enabled features
are installed. Subsystem completion seals their explicit builtin graphs using
V8's `FROZEN` integrity level. Global binding publication also locks bindings
restored from the mutable engine seed. `globalThis` is a locked binding; the
global object remains extensible for application globals and host capabilities.

`VerifyAndCaptureZigIntrinsics` independently traverses native-context roots and
standard global bindings, verifies frozen objects and immutable bindings, and
captures the inventory. It never freezes objects, changes descriptors, or deletes
globals; a missed subsystem root fails context creation. Traversal reads data
fields and accessor pairs directly, without invoking getters or constructing
Segmenters. Internal tables, embedder data, globals, and extras bindings are
excluded from sealing.

WebAssembly is built in (`v8_enable_webassembly=true`, the default; pass
`-Dwebassembly=false` to compile it out). `WasmJs::Install` exposes the namespace and
`CompleteZigWasmIntrinsics` (patch 0007) seals its whole graph through the context's
preinstalled `WebAssembly` object, then the global binding becomes immutable like the others.
Custom snapshots serialize only the preinstalled object, because the JS-API callbacks that
`Install` creates are not snapshot external references; such contexts do not expose
`WebAssembly`. ShadowRealm's installer returns without installing its API. `v8.has_webassembly`
reports the measured build capability. Toggling Wasm requires rebuilding the engine,
regenerating bindings, and recreating snapshots; previous archives and snapshots are incompatible.

SharedArrayBuffer and Atomics remain available with frozen intrinsic objects and
locked global bindings. Blocking `Atomics.wait()` is controlled per isolate by
`Isolate.CreateParams.allow_explicit_blocking_api` (Zig default: false) and can be changed
for existing contexts with `Isolate.setAllowExplicitBlockingApi`. Managed runtimes default
to false; opt in with `Runtime.Options.allow_explicit_blocking_api = true`. This switch
does not disable nonblocking atomic operations or `Atomics.waitAsync()`.

RegExp legacy match-state accessors (`input`, aliases, and `$1`–`$9`) are omitted
at engine installation. Standard accessors such as `Symbol.species` remain.
`Date` is reduced to `Date.now()`: the constructor throws for both call and `new`,
`Date.parse`, `Date.UTC`, and every `Date.prototype` member are omitted, and
`Date.prototype` is an empty frozen object (`v8-no-date.patch`). Use Temporal
for calendar, time zone, and instant arithmetic; building without Temporal
leaves no date functionality beyond `Date.now()`.
When Temporal is enabled, its initializer runs directly before finalization
rather than leaving properties that replace themselves on first access.

## Native stack-trace configuration

`Error.stackTraceLimit` is not installed or read. Each native context owns a
serialized numeric setting, exposed only by `Context.getStackTraceLimit()` and
`Context.setStackTraceLimit(limit)`. `StackTraceLimit` is a tagged union:
`.unlimited`, `.{ .limited = frames }` (`u31`), or `.none`. The default is
`.{ .limited = 10 }`; `.limited = 0` is equivalent to `.none`, and getters
canonicalize zero to `.none`. Unlimited uses V8's maximum native frame limit.

Managed callers can supply `Scope.Options.stack_trace_limit` and use the Scope
getter/setter, which enter the context themselves. Raw callers must enter the
owning isolate on its thread and keep a HandleScope live. Changes affect future
captures, not errors already created. A forged JavaScript value or accessor with
the old name has no effect. Inspector-specific capture requests remain separate.
Finalized custom snapshots preserve their limit; fresh contexts and restored
construction seeds initialize from the engine default before managed options
are applied.

The build's `mksnapshot` process disables finalization only for the extensible
engine seed snapshot. Runtime contexts restored from that seed install enabled
features and finalize before exposure. Application `SnapshotCreator` contexts
finalize before exposure and serialize their graph and immutable descriptors.
Restoring a finalized custom context skips feature installers; it preserves
the feature set selected when that context was created. Create a new snapshot
to change that feature set. Trusted hosts must leave `zig_harden_intrinsics`
enabled for these guarantees; managed scope creation rejects an empty inventory.

## Supported entries and trust boundary

Names are V8 builtin names, not ECMAScript `%…%` notation or numeric builtin IDs.
The table covers functions created through `SimpleInstallFunction`,
`InstallFunctionWithBuiltinId`, and `InstallFunctionAtSymbol`. It is not a complete
ECMAScript intrinsic catalogue: constructors, accessors, and functions installed
through other paths may be absent. A name that identifies multiple distinct
installed functions is ambiguous and unavailable. Unknown names, uninstalled
compiler stubs, and ambiguous entries return `null`.

This is a **host-only API**. Keep it out of the guest global and do not forward
guest-controlled names without a host policy. In particular, managed scopes
remove certain globals as part of their policy; an unrestricted intrinsic lookup
must not be granted as a way around that policy. Trusted JavaScript can receive
specific functions through a private initializer argument or closure.

The result is the original frozen function object. Invoke it through the native `Function.call`
API with an explicit receiver, rather than looking up its JavaScript `.call`.
Calling an intrinsic still follows ECMAScript behavior, including applicable
getters, proxy traps, callbacks, thenables, and species hooks. This API does not
replace validation or context hardening.

## Maintaining the V8 patch

The engine changes live in `build-tools/patches/v8/` (intrinsics, hardening, no-date, mimalloc), applied in
name order. The normal build
runs `build-tools/scripts/apply-patches.sh` after fetching V8 and before GN generation.
It records applied patches in the checkout, reapplies only a changed tail, and
fails the build with an explicit rebase instruction on conflict (see
`build-tools/README.md`). The patches modify native-context fields,
bootstrap installation/finalization, and the seed snapshot policy; no generated
V8 file is hand-edited.

When upgrading V8:

1. Update the V8 version and apply or rebase the patch against the new checkout.
2. Check that the three installer hooks still cover the methods you depend on,
   and update builtin names if V8 renamed them.
3. Run `zig build gen`, `zig build check-generated`, and `zig build test` with
   the usual build options. The intrinsic tests cover identity, tampering, realm
   ownership, garbage collection, hidden prototypes, immutable globals, omitted
   legacy accessors, and a frozen custom snapshot round trip.

The added native-context field changes V8's internal layout. Rebuild the engine
and recreate snapshots after changing this patch or upgrading V8. A prebuilt
library must include both the same patch and the intrinsic lookup shim; an
unpatched stock V8 archive is not a substitute.

The tables use one tagged slot per V8 builtin and one per intrinsic graph object
per context, plus references to objects that must remain alive. Snapshotting avoids recapturing them
when restoring a context, but does not remove that memory cost.
