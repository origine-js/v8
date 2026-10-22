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
reusing the cached profile. Profile files are not committed or rewritten.

## Permanent exclusions

The following 16 builtins are excluded from PGO **even if a future graph matches
Google's hash**, by explicit project policy. This decision is independent of the
unpatched upstream comparison. Their implementations, hardening and tests remain
enabled; only their optimization hints are ignored.

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
`ProfileDataFromFile::TryRead`, returning no profile for these names. It also
disables profile-based builtin reordering, so excluded entries cannot affect that
optimization. Matching entries still guide branch optimization.

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
or layouts used by its generated code can also differ. The exact cause of these
16 mismatches has not been established.

**Unpatched V8 15.8.30 accepts Google's baseline.** A separate V8 source tree at
the same commit, with no V8 source patches and the same macOS arm64 GN arguments,
successfully generated a snapshot with `--abort-on-bad-builtin-profile-data`.
All 1,012 Google hash records matched, including the 16 excluded names.
This isolates the difference to the downstream V8 patch series rather than those
shared build settings. It does not imply that these 16 builtin implementations
were directly edited. The explicit exclusion policy remains unchanged.

## Verification

`zig build build-v8` downloads/verifies the baseline and rebuilds the hardened
engine. Snapshot output reports `Ignoring builtin PGO for <name> (explicit
downstream exclusion)` for each excluded entry; any other incompatible entry
reports `Rejected profile data for <name>`.

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
production build, whose explicit exclusions remain in force.
