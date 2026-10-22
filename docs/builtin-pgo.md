# Google builtin PGO baseline

Release desktop builds use V8's builtin PGO, not C++ compiler PGO. All existing
hardening remains required and enabled. Debug and iOS builds default to no PGO;
`-Dbuiltin_pgo=false` selects an unprofiled comparison build in a separate output
directory.

## Source and integrity

- V8: `15.8.30`, commit `a98309795399032afd2f191adaa94ed6e9918437`.
- Google profile version: `15.8.30.0` (the fourth component is required in the URL).
- [Google metadata](https://storage.googleapis.com/chromium-v8-builtins-pgo/by-version/15.8.30.0/meta.json).
- [Google x64 baseline](https://storage.googleapis.com/chromium-v8-builtins-pgo/by-version/15.8.30.0/x64.profile).
- x64 baseline SHA-256: `dba8848e975875672616328a4647251993c80fcbbee6afc37e77377727beaf01`.

V8 supports using the x64 builtin profile for arm64. The downloader verifies the
metadata's source revision and version, downloads the unchanged profile into the
local V8 cache, and records a SHA-256 receipt. It verifies that receipt before
reusing the cached profile. Google profile files are not committed or rewritten.

## Configuration-specific entries

The following 16 builtins use locally measured profiles on **macOS aarch64 only**.
On other targets they remain explicitly excluded from PGO, even if a future graph
matches Google's hash. Their implementations, hardening and tests remain enabled.

| Builtin | Google hash | Hardened graph hash |
|---|---|---|
| RunMicrotasks | `c94aff38` | `de617e6d` |
| AsyncFunctionEnter | `f6c76491` | `0a9e6b05` |
| AsyncFunctionAwait | `18947d89` | `280697d4` |
| AsyncGeneratorYieldWithAwait | `2929ec50` | `cf76815e` |
| AsyncGeneratorReturn | `0772bb03` | `2c096f35` |
| AsyncGeneratorPrototypeNext | `e8a9bfc6` | `0893dd84` |
| AsyncGeneratorPrototypeReturn | `1307d9f5` | `1f6cef32` |
| AsyncGeneratorAwait | `31484beb` | `27d6ebee` |
| FulfillPromise | `2ae57ad2` | `f7bb5d7d` |
| RejectPromise | `3d9c3870` | `116cee91` |
| NewPromiseCapability | `de3ca688` | `1bbd1451` |
| PromiseReject | `1016b786` | `f2a59b77` |
| PromiseConstructor | `0b8887fb` | `eff24b43` |
| PromiseResolve | `fc1f5966` | `00132416` |
| PromisePrototypeThen | `f76b3778` | `201a7ae9` |
| CreateTypedArray | `e8068af7` | `c1b3e7d5` |

Patch `0009-pgo-compatible-builtins.patch` implements the exclusions in
`ProfileDataFromFile::TryRead`, returning no profile for these names by default. It also
disables profile-based builtin reordering, so excluded entries cannot affect that
optimization. Patch `0010-macos-arm64-custom-pgo.patch` permits these names only
when the build explicitly selects the validated macOS arm64 overlay. That mode
requires `--abort-on-bad-builtin-profile-data`; mismatches stop snapshot creation.
Matching entries still guide branch optimization. Reordering remains disabled.

For other builtins, V8 retains its graph-hash comparison. An incompatible entry
emits a warning and is discarded. No hash is changed, and no mismatched profile is
applied to generated code.

## Measured acceptance

On macOS arm64, before applying the explicit exclusions, the hardened V8 build
rejected the 16 entries above and matched 983 entries. Another 13 of Google's
1,012 builtin hash records name Date builtins removed from this build, so only
999 records were applicable. Strict snapshot generation aborted at `RunMicrotasks`.

The absent records are `DatePrototypeGetDate`, `DatePrototypeGetDay`,
`DatePrototypeGetFullYear`, `DatePrototypeGetHours`, `DatePrototypeGetMinutes`,
`DatePrototypeGetMonth`, `DatePrototypeGetSeconds`, `DatePrototypeGetTime`,
`DatePrototypeGetUTCDate`, `DatePrototypeGetUTCFullYear`, `DatePrototypeGetUTCMonth`,
`DatePrototypeToPrimitive`, and `DatePrototypeValueOf`.

A graph-hash mismatch does **not** establish that the corresponding builtin's
source implementation was edited. Constants, shared graph nodes, build settings,
or layouts used by its generated code can also differ.

**Unpatched V8 15.8.30 accepts Google's baseline.** A separate V8 source tree at
the same commit, with no V8 source patches and the same macOS arm64 GN arguments,
successfully generated a snapshot with `--abort-on-bad-builtin-profile-data`.
All 1,012 Google hash records matched, including the 16 excluded names. However,
that initial reference used the stock `.gn` while production uses
`--root=. --dotfile=zig/.gn`. Identical `args.gn` files do **not** imply identical
effective GN settings. The initial comparison therefore did not isolate the
hardening patch series.

## Configuration diagnosis

The production dotfile supplies these defaults, inherited from the existing
embedder configuration:

| GN setting | Stock V8 default | Production default |
|---|---|---|
| `v8_enable_javascript_promise_hooks` | `false` | `true` |
| `v8_promise_internal_field_count` | `0` | `1` |
| `v8_array_buffer_internal_field_count` | `0` | `2` |
| `v8_array_buffer_view_internal_field_count` | `0` | `2` |
| `v8_typed_array_max_size_in_heap` | `64` | `0` |

Initial `V8.TFMachineCode` graphs captured before PGO validation show that
`AsyncFunctionEnter` has 306 nodes with stock defaults versus 419 in production.
Production includes a JavaScript context promise-hook call and its exception
reporting path. `CreateTypedArray` has 4,393 nodes with stock defaults versus
4,436 in production, including additional embedder-field initialization stores
and a different heap-allocation threshold constant.

**The 16 mismatches are caused by the embedder configuration, not by the
hardening patches.** A second control built unpatched V8 using the production
dotfile. Its `v8_initializers` compiler defines, include paths, C flags, and C++
flags were identical to production's. The V8 source tree was clean at the pinned
commit. It reproduced the exact same 16 rejected names **and hash values**.

| V8 source | Effective defaults | Matching Google records | Mismatched | Absent |
|---|---|---:|---:|---:|
| Unpatched | Stock `.gn` | 1,012 | 0 | 0 |
| Unpatched | Production `zig/.gn` | 996 | 16 | 0 |
| Hardened | Production `zig/.gn` | 983 | 16 | 13 |

All 999 Google entries present in both production-configured builds had
identical graph hashes. The 13 absent records are the deliberately removed Date
builtins. Removing hardening therefore does not restore compatibility for these
16 profiles. The initial stock-reference result was real, but attributing it to
the absence of hardening was incorrect.

The concrete code-generation mechanisms are:

- The 15 promise/async/microtask builtins use promise-hook or promise-allocation
  helpers. `src/builtins/promise-misc.tq` includes JavaScript context hooks under
  `V8_ENABLE_JAVASCRIPT_PROMISE_HOOKS`; `RunAllPromiseHooks` in
  `src/builtins/builtins-microtask-queue-gen.cc` adds before/after context-hook
  paths. `AllocateJSPromise` and `ZeroOutEmbedderOffsets` in
  `src/builtins/builtins-promise-gen.cc` use `Promise::kEmbedderFieldCount`,
  changing allocation size and emitting extra initialization stores. In the
  captured `AsyncFunctionEnter` graph, promise allocation grows from 20 to 28
  bytes, with stores for the extra field and a hook call/exception-reporting path.
- `CreateTypedArray` uses `SetupTypedArrayEmbedderFields` and
  `AllocateEmptyOnHeapBuffer` from `src/builtins/builtins-typed-array-gen.cc`,
  which emit initialization for the configured extra fields. Its allocation
  logic in `src/builtins/typed-array-createtypedarray.tq` also uses the configured
  `kMaxTypedArrayInHeap` threshold. Production has extra initialization stores
  and a zero threshold rather than stock V8's 64-byte threshold.

V8 hashes the initial graph's operation/input structure in
`src/compiler/pipeline.cc`, before applying PGO. Extra branches, calls, stores,
and changes to shared constant nodes can invalidate a profile even when the
builtin's own source file is unchanged. Runtime hook activation is not required:
the enabled feature already changes the generated graph.

These defaults predate the 15.8 upgrade (they are present in the rusty_v8
integration commit `8e23a39`). No production defaults, hardening, profile contents,
or exclusions were changed during this diagnosis. Google profiles
are simply incompatible with this embedder configuration for these 16 entries;
the builtin implementations remain enabled and valid.

## Locally trained profiles

A separate [configuration-matched profile](../build-tools/pgo/README.md) is now
available for all 16 excluded builtins on macOS arm64. It contains actual
execution counters and branch hints from the hardened engine, with all 16 hashes
validated against production. Compressed raw counters and a provenance manifest
are retained beside the profile. The manifest also records successful strict
reader validation against the configuration-matched reference.

The training workload is focused and synthetic; no performance improvement is
claimed. Release builds enable these profiles **only on macOS aarch64**. The
preparation script verifies the recorded training configuration, source revision,
dotfile and artifact digests, and writes a separate merged cache profile and
receipt. It replaces Google's records for exactly these 16 names, preserving
measured hashes and counters. Google's original baseline remains unchanged.
Other targets retain the 16 exclusions; Linux custom training is deferred.

The training manifest's `production_enabled: false` describes the generation-time
state, not the current build selection. `v8_zig_custom_builtin_pgo=true` and the
`origine-mac-arm64.profile` input select the overlay. `-Dbuiltin_pgo=false`
disables both Google and custom builtin PGO.

The activated production generator accepted the merged profile with strict hash
checks: **999 matching, zero mismatched, 13 absent Date entries**. It loaded all
16 custom entries without an exclusion. As a negative control, the same generator
and strict flags rejected Google's original `RunMicrotasks` record. Profile
validation therefore remains active; the overlay supplies measured compatible
data rather than bypassing the checks.

## Verification

`zig build build-v8` downloads/verifies the baseline and rebuilds the hardened
engine. On macOS aarch64 snapshot output reports `Loading configuration-matched
builtin PGO for <name>` for each custom entry; all applicable entries must pass
strict hash validation. Other targets report `Ignoring builtin PGO for <name>
(explicit downstream exclusion)` for the 16 names; other incompatible entries
report `Rejected profile data for <name>` and discard that entry.

For diagnostic comparison, run a snapshot generator built **without the exclusion
patch** against the unchanged profile:

```sh
./mksnapshot --target_os=mac --target_arch=arm64 --predictable --no-use-ic \
  --turbo-elide-frames --turbo-profiling-input ../../tools/builtins-pgo/profiles/x64.profile \
  --warn-about-builtin-profile-data \
  --dump-builtins-hashes-to-file=/tmp/v8-builtin-hashes.txt \
  --embedded_src /tmp/v8-pgo-probe.S --startup_src /tmp/v8-pgo-probe.cc
```

Use `--abort-on-bad-builtin-profile-data` instead of the warning flag to verify
strict all-entry acceptance. Keep this diagnostic separate from the hardened
production build. The macOS aarch64 production build instead validates the merged
profile strictly; other targets retain the explicit exclusions.

Compare generated hashes with the unchanged baseline using:

```sh
uv run build-tools/scripts/compare-pgo.py /path/to/x64.profile /tmp/v8-builtin-hashes.txt
```

`--expect-mismatches` and `--expect-absent` assert the expected counts and exit
nonzero on a difference. `--compare /path/to/other-hashes.txt` also compares both
builds' hashes for shared Google entries; `--expect-differences` asserts that
comparison's difference count. Hash dumping computes the initial hashes even
for builtins deliberately excluded from applying PGO. Use a fresh dump file for
each run: V8 appends to an existing hash dump.

To repeat the controlled comparison, prepare an isolated unpatched checkout with
the same dependencies and `args.gn` as production. Copy the production
`build-tools/gn/.gn` to its `zig/.gn`, then invoke GN with an explicit source root:

```sh
gn --root=. --dotfile=zig/.gn gen out/control
autoninja -C out/control mksnapshot
```

The explicit `--root=.` is required for this invocation to honor the alternate
dotfile. Verify the generated `obj/v8_initializers.ninja` settings rather than
assuming that `args.gn` alone describes the configuration. Run the diagnostic
snapshot command above from `out/control`. Then, from the `lib/v8_zig` root:

```sh
uv run build-tools/scripts/compare-pgo.py /path/to/x64.profile \
  /tmp/unpatched-embedder-hashes.txt --expect-mismatches 16 --expect-absent 0 \
  --compare /tmp/hardened-hashes.txt --expect-differences 0
```

For the pinned macOS arm64 configuration this reports 999 shared Google entries
and zero differences. The stock-default reference should instead report zero
mismatches and zero absent entries. `--trace-turbo` together with
`--trace-turbo-filter=AsyncFunctionEnter` or `CreateTypedArray` captures the initial
`V8.TFMachineCode` graph for inspecting the added paths and stores.
