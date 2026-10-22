# build-tools

Everything the build runs that is not Zig source.

| Path | Purpose |
| --- | --- |
| `patches/v8/` | Ordered patch series applied to the V8 checkout |
| `patches/partition_alloc/` | Series for `third_party/partition_alloc` (own git root) |
| `patches/icu/` | Series for `third_party/icu` (own git root) |
| `scripts/` | Build helpers: fetch, patch apply/author, ICU compression, archive bundling, startup measurement |
| `gn/` | `BUILD.gn` and `.gn` copied into the V8 checkout at `zig/` |
| `bindgen/` | `layout.zon` and `typemap.zon`, inputs of `zig build gen` |

## Patch series

Each directory holds `NNNN-name.patch` files applied in name order, as plain
`git apply` patches against the pinned V8 version. Current V8 series:

1. `0001-intrinsics` retains original builtin functions in a context table
2. `0002-hardening` freezes the intrinsic graph and builtin globals
3. `0003-no-date` reduces `Date` to `Date.now()` (needs 0002)
4. `0004-mimalloc` routes V8 allocations through mimalloc
5. `0005-no-date-cleanup` deletes the now-unreachable Date builtins, CSA getters and compiler
   reducers, and revives a deserialized Date as a `Temporal.Instant` (needs 0003)
6. `0006-immutable-installers-native-stack` moves hardening into installation and
   subsystem completion, verifies the inventory without freezing, skips
   ShadowRealm, adds native per-context stack-trace configuration, and publishes
   immutable builtin bindings restored from the extensible engine seed
7. `0007-wasm-hardening` installs and seals the WebAssembly namespace
8. `0008-pgo-context-layout` appends private context fields after upstream slots,
   preserving upstream field offsets for Google's builtin PGO baseline
9. `0009-pgo-compatible-builtins` explicitly excludes the 16 builtins listed in
   [builtin PGO](../docs/builtin-pgo.md), disables profile-based reordering, and
   retains hash checks for all remaining entries. Mismatches warn and discard
   optimization data without changing the baseline or hardened code.

The build enables WebAssembly by default. Bindings are measured against
that configuration; changing Wasm requires rebuilding, regenerating bindings,
and recreating snapshots. Hardening changes also require new engine archives
and snapshots because the native context layout now includes a stack-trace limit.

`scripts/apply-patches.sh <checkout> <series-dir>` runs in the build before GN. It records
what it applied in `<checkout>/.zig-patches`, so editing, renumbering, or removing a patch
reverts only the changed tail and reapplies it. A patch that does not apply stops the build
naming the file; never skip it silently.

### Changing the engine

1. `zig build` so the checkout holds the full series.
2. Edit files in `.lp-cache/v8-<version>/` (or `third_party/icu`, `third_party/partition_alloc`).
3. `sh build-tools/scripts/new-patch.sh <checkout> build-tools/patches/v8 <name> [new files...]`
   writes the next numbered patch from the diff against the series baseline and reverts the edits.
4. `zig build`; the new patch is applied through the series.

To change an existing patch, edit it in place (or regenerate it); the applier reverts and
reapplies from that patch on.

### Upgrading V8

Bump the version, run the build, and rebase each failing patch in order: apply the series up to
the failing patch, fix the conflict in the checkout, and regenerate that patch.
Release builds fetch Google's matching builtin profile through `scripts/download-pgo.py`
before GN generation. Metadata must match the source commit, and `mksnapshot`
retains profile-hash validation, discarding incompatible entries with warnings.
Never alter profile hashes to accept changed code. Profile-based builtin reordering
is disabled because the explicit exclusions must also be excluded from reordering.
Branch optimization still uses matching, non-excluded profiles.

`scripts/train-pgo.py` can generate configuration-matched profiles for the 16
excluded builtins using a separate hardened profiling build. See
[the training workflow and generated artifacts](pgo/README.md). Generation does
not enable the profiles or change the production exclusion policy.
