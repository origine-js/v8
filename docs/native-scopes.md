# Native V8 scopes

The managed API in `src/managed.zig` creates separate V8 contexts inside one isolate.
It uses native scripts, ESM linking, synthetic modules, and promises. A project-owned
bootstrap hardens contexts; there is no SES dependency.

## Implementation checkpoints

The implementation was built in the following order, running the library suite
at each checkpoint:

| Step | Review focus | Validation |
| --- | --- | --- |
| 1 | Runtime/scope ownership, tokens, strict evaluation, retained handles | Independent globals, foreign-global denial, context restoration |
| 2 | Pristine-context bootstrap and intrinsic inventory | Prototype mutation and string-code-generation attacks |
| 3 | Explicit hardened exports | Identity, private state, descriptor traversal, exotic rejection |
| 4 | Resolver/loader contracts and native ESM graphs | Cycles, TLA, defining-scope imports, failure propagation |
| 5 | Pending tokens and completion | Concurrent requests, out-of-order completion, cancellation |
| 6 | Optional import-map adapter | Scoped/prefix mappings, blocked targets, virtual backends |
| 7 | Shell, native capabilities, combined adversarial tests | Private native state, forged receivers, callbacks and exceptions |

Tests are grouped by these step numbers in `src/managed/test.zig`.

## Initialization and ownership

Initialize the V8 platform and engine through `v8.V8.initialize()` before constructing a runtime. `Runtime.create` returns a heap-allocated `*Runtime` with a stable address; release it with `destroy`:

```zig
const m = @import("managed.zig");
const rt = try m.Runtime.create(allocator, .{});
defer rt.destroy();
const scope = try rt.createScope(.{});
const result = try scope.eval("({ answer: 42 })", "app:/entry.js", null);
defer result.deinit();
```

`eval` forces strict mode for all guest scripts, including scripts with a hashbang,
and returns an owned `v8.Global.Of(v8.Value)`. ESM is inherently strict. Neither
entry point has a sloppy-mode opt-out; no source directive is needed.
`v8.V8.initialize()` enables V8's native `--use-strict` flag before engine initialization.
This is process-wide and also affects raw scripts compiled through the bindings.
Evaluation compiles the original source directly, without allocating or prepending
a strict-mode directive, so hashbangs and source positions are preserved. If the
embedder initializes V8 externally, it must set `--use-strict` before initialization;
V8 freezes its flags afterward. This is not a per-context compile option.
`importModule` returns an owned `v8.Global.Of(v8.Promise)`. Dispose these handles
before disposing the runtime. To dereference them, enter the isolate and open a
handle scope; enter the appropriate context before performing context operations.
`eval` reports script failures as `error.JavaScriptException`; module failures are
JavaScript promise rejections containing the original exception when available.

Scope storage and originating contexts live until runtime teardown because
exported functions may retain them. There is no independent scope destruction or
capability revocation. Callback data must stay alive until runtime teardown.
The host must keep resolver/normalizer policy immutable and use the owning isolate
thread for every operation. Callbacks must not re-enter runtime lifecycle or
completion operations; queue asynchronous completions until the callback returns.

`rt.pump()` drains managed promise jobs and advances imports. `rt.pumpPlatform(platform)`
also drains V8 foreground tasks with the isolate entered. Neither method is a
scheduler with per-scope fairness or a CPU deadline.

### Allocators

`Runtime.create(metadata_alloc, .{})` preserves the native V8 backing-store allocator.
The metadata allocator backs managed scopes, import maps, loader metadata, and
other Zig runtime storage; it does not allocate the V8 GC heap.

Pass `Options` to `Runtime.create` to choose backing-store allocation independently:

```zig
const mimalloc = @import("mimalloc.zig");
const rt = try m.Runtime.create(metadata_alloc, .{
    .array_buffer_allocator = .{ .zig = mimalloc.allocator },
});
defer rt.destroy();
```

The `.zig` option accepts any thread-safe `std.mem.Allocator`. It creates and owns
an `ArrayBuffer.Allocator.fromZig` adapter, whose descriptor lives at a stable
address independently of the runtime value. The adapter allocates its descriptor
and 16-byte-aligned backing stores through the supplied allocator; zeroed requests
are initialized before returning, and failures return null to V8. Its host allocator
state must remain alive through teardown. Release persistent handles and all
standalone/shared backing stores before disposing a runtime with an owned adapter.
An ArrayBuffer allocation failure can become a guest exception; V8's other internal
allocation failures are not universally recoverable Zig errors.

To retain backing stores beyond runtime teardown, own the adapter outside the runtime:

```zig
const aba = try v8.ArrayBuffer.Allocator.fromZig(backing_alloc);
defer aba.deinit(); // After runtime teardown AND release of all backing stores.
const rt = try m.Runtime.create(metadata_alloc, .{
    .array_buffer_allocator = .{ .borrowed = aba },
});
defer rt.destroy(); // Does not destroy the borrowed allocator.
```

The caller must retain both the borrowed native allocator and its Zig allocator
state until the last backing store is released. Allocator callbacks can run on V8
background threads and must not call V8. `fromZig` returns
`error.UnsupportedSandboxAllocator` when the V8 sandbox is enabled, because ordinary
Zig/mimalloc allocations do not reside in the sandbox. Use V8's default allocator
or a separately implemented sandbox-compatible borrowed allocator in that build.

`mimalloc.zig`'s `allocator` has process-lifetime state and supports cross-thread frees;
there is no Zig allocator deinit call. Zig builds the pinned dependency's `src/static.c`
directly and installs `libmimalloc.a` alongside `libv8_zig.a`. C consumers using the
`mi_*` APIs must link the mimalloc archive too. No libc malloc overrides or macOS
malloc-zone interposition are enabled. This selection affects managed metadata
and/or ArrayBuffer backing stores as requested; V8 GC/code pages and unrelated
native malloc/new allocations retain their existing paths. The disabled
`src/alloc.zig` replacement is not imported or modified.

### Slice ownership and lifetimes

These contracts are also documented directly in the Zig `///` comments on each
public function and callback type, so they appear in editor documentation.

Scope methods that catch JS exceptions accept a final `error_info: ?*ErrorInfo`
parameter. Pass `null` to discard details, or pass an `ErrorInfo` initialized with
`.{};` the method releases its previous details on entry. Call `error_info.deinit()`
before runtime teardown. Its `exception` field owns a retained handle preserving
the original thrown value, including objects, primitives, and `undefined`.
A null `exception` field means no exception value was
caught, including engine termination. Hardening errors can also populate the output
when the Zig error is `UnsupportedExport`. Module-map `update` and `get` accept the
same output; `get` returns the cached failure. Ordinary import failures reject the
returned promise and leave `error_info.exception` null.

```zig
var error_info: m.ErrorInfo = .{};
defer error_info.deinit();
const result = scope.eval(source, origin, &error_info) catch |err| {
    if (error_info.exception) |value| inspectException(value);
    return err;
};
defer result.deinit();
```

| API/value | Owner and lifetime |
| --- | --- |
| `eval(source, origin)`, capability names | Caller-owned, borrowed through the call only; V8 copies retained bytes. |
| `error_info` | Optional borrowed `ErrorInfo` output, previous details released on entry; its `exception` field owns a persistent handle. Call `deinit` before runtime teardown. |
| Import specifiers, cache IDs, attribute arrays and nested strings | Caller-owned, borrowed through the public call only; retained entry metadata is deep-copied, including pending loads. |
| `updateImportCache` / `completeLoad` source and exports | Caller-owned, borrowed through the call; names and handles are independently retained. Caller may release inputs after success or error. |
| Import-map construction entries / optional JSON input | Caller-owned, borrowed through `init` / `parseJson` only; map contents are independently copied. |
| `createScope` import map | Caller-owned, borrowed through the call only; each scope owns an independent clone. Normalizer host state stays borrowed through runtime teardown. |
| `Resolver.resolve` inputs | Borrowed only during the callback. Copy anything needed later. |
| Resolver result | Allocate with `request.allocator`; ownership transfers to the runtime. Never return input aliases, static bytes or a different allocator's allocation. |
| Loader request ID/attributes | Runtime-owned immutable bytes until teardown starts; readable during that token's cancellation callback. |
| Loader context/allocator | Borrowed only during the callback. Do not retain or use off-thread. |
| Loader result buffers | Static, request-allocator storage, or host storage kept alive through the enclosing operation. Never return stack bytes or buffers freed on callback return. |
| Direct `ImportMap.resolve(allocator, ...)` result | Caller-owned allocation; free with that allocator. It remains valid after the map is destroyed. |
| Normalizer result | Allocated with its supplied allocator; ownership transfers to its caller. |
| Callback `.data` | Host-owned, stable and alive until consumer teardown returns; the runtime never destroys it. |

Inputs must remain immutable for the duration of their borrow. `[]const u8` alone
does not encode ownership; the function/request/result contract determines it.
Persistent V8 result handles belong to the caller and must be released before
runtime teardown. Local V8 handles are valid only inside their active HandleScope;
escape values from nested scopes before returning them from a callback.

## Sharing and private state

```zig
const owner = try rt.createScope(.{});
const guest = try rt.createScope(.{});
const counter = try owner.eval(
    "new (class Counter { #n = 0; inc() { return ++this.#n; } })()",
    "app:/counter.js",
    null,
);
defer counter.deinit();
try owner.installCapability("counter", counter, null);
try guest.installCapability("counter", counter, null);
```

Capability installation hardens the reachable public graph and installs an immutable
global binding. `scope.harden(value, null)` performs hardening without granting the value.
Records, arrays, functions, and ordinary capability instances preserve reference
identity. Their descriptors, accessor functions, and prototype chains are frozen.
Getter bodies are not invoked while traversing the graph. Cycles are supported.
Hardening can freeze the original graph; it does not make a copy.

Closure state, JS `#private`, and native private/internal fields remain mutable.
Native methods must validate receivers, argument types, and host-state lifetimes;
see the native counter test for a V8 private-key example. Avoid argument coercion
unless you deliberately allow guest execution and handle its exceptions.

Proxies, globals, promises, module namespaces, mutable collection/buffer objects,
iterators, weak references, boxed primitives, and other unsupported exotic values
are rejected as hardened exports. Values must originate in this runtime's managed
contexts. Native functions should be created while a managed context is entered.

Direct calls do not intercept their arguments, results, exceptions, or callbacks.
Capability authors must harden records they return or give to callbacks and must
treat guest arguments as untrusted. A method may return a promise, but its payload
must follow the same sharing contract. There is no automatic property hiding:
public properties remain public. Passing mutable state deliberately grants access.

## Backend-independent modules

A scope accepts either a custom resolver or an import-map configuration, plus a loader:

```zig
fn resolve(_: ?*anyopaque, request: m.ResolveRequest) !m.ModuleId {
    return request.allocator.dupe(u8, request.specifier); // Example opaque-ID policy.
}
fn load(_: ?*anyopaque, request: m.LoadRequest) !m.LoadResult {
    if (std.mem.eql(u8, request.module_id, "demo"))
        return .{ .source = "export const answer = 42" };
    return error.ModuleNotFound;
}
const scope = try rt.createScope(.{
    .resolver = .{ .resolve = resolve },
    .loader = .{ .load = load },
});
const promise = try scope.importModule("demo", null);
defer promise.deinit();
rt.pump();
```

`ResolveRequest` contains a result allocator, entered V8 context, scope ID, specifier, referrer ID,
and import attributes. The resolver supplies canonical logical module identities.
The resolver must allocate its returned ID with request.allocator; it must not
return borrowed input or static storage. Request fields are borrowed only for the
callback duration. Release temporary allocations on success and clean up on failure.
Module IDs have no inherent filesystem meaning.
The loader may use memory, a virtual filesystem, an archive, a network service, or
an explicitly authorized real filesystem. There is no implicit IO or fallback.

`LoadRequest` contains the entered `context`, scope ID, canonical module ID,
completion token, and decoded `import_attributes` (`key`/`value` pairs). Both static
`with { ... }` and dynamic `import(specifier, { with: { ... } })` attributes reach
the resolver and loader. Attributes are copied and sorted by key, with duplicate
keys rejected. Hosts can use `scope.importModuleWithAttributes(specifier, attributes, null)`;
`scope.importModule(specifier, null)` supplies no attributes. The backend decides which
attributes it supports and should reject unsupported keys or values explicitly.
Its `allocator` can allocate returned source/export arrays/names without borrowing
a backend scratch buffer. The runtime owns these allocations; do not free result
allocations or retain/use the allocator after the callback. Asynchronous backend
work must use independently owned storage, then lend it to `completeLoad`.

The context is borrowed for the callback duration only. Do not retain its local
handle across asynchronous work; use an owned persistent handle where needed.
Attribute storage remains valid until runtime teardown.

The loader returns `.source`, `.exports` (named retained values for a synthetic
module), `.exception` (a custom local JS exception), or `.pending`. For example:

```zig
const iso = v8.Isolate.getCurrent();
const exception = v8.Exception.typeError(v8.String.initUtf8(iso, "Module denied")).?;
_ = exception.toObject(request.context).?.createDataProperty(
    request.context,
    v8.String.initUtf8(iso, "code").name,
    v8.String.initUtf8(iso, "DENIED").name.primitive.value,
);
return .{ .exception = exception };
```

Custom exceptions are retained and propagated unchanged to the import rejection.
A callback may also call `iso.throwException(exception)` and return a Zig error;
the thrown JavaScript exception takes precedence over the Zig error name.
Source/exports are consumed during the operation: retain
the backing storage through the enclosing import/completion call, and keep supplied
export handles alive through that call. The runtime retains its own export handles.
Synthetic export values must pass the hardened-sharing checks.

For pending loads, retain `request.token` and later call:

```zig
try rt.completeLoad(token, .{ .content = .{ .source = module_source } });
// Or: try rt.completeLoad(token, .{ .failure = error.ModuleNotFound });
// Or: try rt.completeLoad(token, .{ .exception = retained_js_exception });
rt.pump();
```

Tokens are runtime-issued and single-use. Complete only after the loader returns,
on the isolate thread; duplicate or unknown tokens return `error.StaleLoadToken`.
The `.exception` completion borrows an owned persistent handle from this runtime;
the runtime retains its own copy, so the caller can release its handle after completion.
An optional loader `cancel(data, token)` callback releases outstanding backend work
at teardown. Pending import promises are rejected at teardown; no guest microtasks
are run during disposal. The backend must stop sending completions after teardown.

Static and dynamic imports share one resolver. Registries deduplicate loads and
module instances within each scope by canonical module ID and normalized attributes.
Different attributes receive different instances and loader checks; equivalent
attribute sets in different orders deduplicate. Distinct scopes get distinct instances.
Cycles are linked only after the graph is available. Dynamic imports fulfill with
namespaces after evaluation and top-level `await`. Imports inside exported functions
retain the function's originating context/policy. `import.meta.url` is the canonical
logical module ID. Non-evaluation import phases remain unsupported.

## Module maps and cache mutation

Each scope owns a `module_map` mapping resolved specifiers and normalized attributes
to cached V8 module instances. The pipeline is specifier → optional import-map or
resolver rewrite → module-map lookup → loader on a miss. Without a resolver or
import map, the specifier is used unchanged. Host code can populate, inspect,
delete, replace, or clear these mappings:

```zig
const key: m.ModuleMapKey = .{ .module_id = "app:/plugins/main.js" };
try scope.module_map.update(key, .{ .source = "export const version = 2" }, null);
if (try scope.module_map.get(key, null)) |module| {
    defer module.deinit(); // Caller-owned retained V8 Module; release before rt.destroy().
}
const removed = try scope.module_map.delete(key);
const cleared = try scope.module_map.clear();
_ = removed;
_ = cleared;
```

Keys use the resolver's canonical IDs, not unresolved import specifiers. Set
`key.import_attributes` to operate on a particular attribute set; omission targets
the no-attribute entry. Equivalent attribute sets in different orders share a key.
All operations are per-scope and host-only. `get` does not resolve or load: it returns
null for absent/pending mappings and an error for cached failures. Inputs, including
nested strings and export handles, are borrowed only through the call; retained
data is copied. The older `Scope.*ImportCache` methods and `ImportCacheKey` alias
operate on this same module map.

Deletion and replacement also invalidate transitive cached static dependents,
including cycles. Deletion returns the total number of invalidated entries, or zero
if the target was absent. Clearing returns the number of active lookups removed.
Future imports reload invalidated modules through the backend. Replacement accepts
JavaScript source or hardened synthetic exports and inserts the module if absent;
the target content bypasses the loader, while its dependencies use normal loading.
Replacement compiles immediately; linking and evaluation happen on import. Failed
replacement content is cached as a failure until it is deleted or replaced again.

Existing namespaces, functions, and linked modules retain their original instances;
this is cache invalidation, not in-place rewriting of existing ESM bindings. Dynamic
imports made later use the current cache. In-flight imports continue and their load
tokens remain valid, even when their lookup is deleted or replaced. Eviction does
not cancel that work. Retired module metadata/handles are retained until runtime
teardown to preserve those references and callbacks; deletion is not immediate
memory reclamation. Reentrant cache mutation during resolver/loader callbacks or
the synchronous module-evaluation call returns `error.ImportCacheBusy`.

## Import maps and URL normalization

Each scope can have its own **import map**, which rewrites a specifier to another
specifier. The result becomes the key in that scope's **module map**, which maps
and caches actual V8 modules. Both maps are independent between scopes.

```zig
var map = try m.ImportMap.init(allocator, .{
    .base_url = "app:/maps/imports.json",
    .urls = m.virtual_urls,
    .imports = &.{.{ .key = "demo", .target = "./demo.js" }},
});
defer map.deinit();
const scope = try rt.createScope(.{
    .import_map = &map,
    .loader = .{ .load = load },
});
```

`ImportMap.init` takes typed `imports` and referrer `scopes` entries and normalizes
and copies their strings. For JSON input, callers can instead use
`ImportMap.parseJson(allocator, json, .{ .base_url = base, .urls = urls })`.
Scope creation accepts a map, clones it, and never parses JSON. A caller can reuse
the same map for multiple scopes and deinitialize it immediately after creation;
the normalizer's host state must remain alive until runtime teardown. Each scope's
copy remains immutable. Matching supports `imports`, referrer `scopes`,
exact entries, longest-prefix entries, null blocked targets, and fallback through
less-specific matching scopes. Prefix results cannot escape the mapped target.
Malformed maps, invalid targets, and duplicate normalized keys fail map construction rather
than using browser-style warning-and-ignore recovery. There is no map mutation API.
In the example, the loader receives `app:/maps/demo.js`, rather than the original
specifier `demo`; it must handle that canonical identity.

Bare V8 does not provide a browser URL parser. The adapter therefore accepts a
`URLNormalizer` callback that returns canonical absolute URLs using the supplied
allocator; results must not alias input. The callback must release temporary
allocations and clean up on failure. Direct map.resolve(allocator, specifier, referrer)
calls return caller-owned bytes that must be freed with that allocator. Resolution
does not retain temporary data in the immutable map. Supply a WHATWG URL implementation for full browser URL semantics,
including HTTP/file URLs and international hostnames. URL normalization is separate
from module storage and does not grant IO authority.

The included `virtual_urls` helper is a strict ASCII hierarchical virtual-URL subset,
such as `app:/a/b.js`. It uses RFC-style resolution, normalizes dot segments, rejects
encoded path separators/authorities, and deliberately rejects browser special
schemes (`http`, `https`, `file`, `ftp`, `ws`, `wss`). It is not a WHATWG URL parser.
Opaque non-URL identities can use a custom resolver without the map adapter.

## Boundary and maintenance

The intrinsic inventory targets V8 14.7.173.20. Update and test it whenever V8 changes.
Scope creation rejects other engine versions until the inventory is updated.
Built-in bindings and prototype graphs are immutable; scope-local globals remain
writable. String code generation, WebAssembly, shared memory, and ShadowRealm are
disabled. V8 freezes the original Date methods and ordinary Date prototype, and
omits RegExp legacy static accessors during installation. Hidden prototypes are
read directly from native-context maps, without constructing Segmenters. These
engine guarantees also apply to raw contexts; see [engine finalization](intrinsics.md#engine-finalization).
Prototype hardening does not repair unsafe application merge
operations or constrain authority intentionally returned by a capability method.

This is a JS-level capability boundary inside one isolate. It does not contain engine
vulnerabilities, memory/CPU exhaustion, or timing side channels. There are no independent
memory quotas, fairness guarantees, or automatic termination of an infinite loop.

The experimental loader types are replaced. Low-level dynamic-import callbacks now
return `v8.MaybeHandle`, matching V8's nullable promise-handle ABI; existing callbacks
should return `promise.object.value.data.handle`. Microtask queue deinitialization now
deletes its allocation as well as running its destructor.

Run `zig build test`, `zig build check-generated`, and `zig build check-bindings`.
For macOS configurations requiring the older installed SDK, add
`-Dmac_sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
Run `zig build shell` with the same configuration; switch scopes with `:a` and `:b`.

Module-map lookups use operation-local scratch storage. Only new module entries
retain IDs, canonical attributes, keys, and dependency metadata. Growing module-map
containers use the runtime allocator and release their backing buffers at teardown.
