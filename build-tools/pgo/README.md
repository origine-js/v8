# Configuration-matched builtin PGO

The [macOS arm64 profile](profiles/15.8.30/mac-arm64/builtins.profile) contains
measured PGO data for the 16 builtins excluded from Google's baseline. It was
generated with V8 15.8.30, our embedder defaults, and all production hardening.
It is **not enabled in production**: the permanent exclusion policy remains in
force, and Google's downloaded baseline is unchanged.

This is a focused synthetic training workload, not a benchmark result or a
claim of improved application performance. It covers ordinary and rejected
promises, thenables, subclass/species paths, async functions, async-generator
next/return/await paths, and typed arrays from multiple input kinds. It runs
8,000 iterations with context promise hooks off and another 8,000 with them on.
It checks that hardened intrinsics remain frozen and Date.parse remains absent.

## Artifacts

The profile directory contains:

- `builtins.profile`: standard V8 profile records for exactly the 16 target
  builtins, including branch hints, execution counts, and measured graph hashes.
- `counters.log.gz`: the original execution counters, compressed without a
  timestamp. These are retained so hints can be audited or regenerated.
- `manifest.json`: V8 revision, configuration, source-diff and tool/workload
  fingerprints, artifact SHA-256 digests, measured builtin entry counts, hint
  counts, and validation results.

All 16 builtins executed and produced branch hints using V8's standard
`get_hints.py` thresholds: at least 1,000 executions of the chosen branch
destination and a 40:1 ratio. RunMicrotasks enters once to drain the workload's
microtask queue; its loop blocks execute many times and supply the measured
branch counts. An entry count of one does not mean its loop hints were invented.

Every generated hash matches a fresh initial-graph dump from the **hardened
production mksnapshot**. Additional strict-reader validation used the temporary
unpatched V8 reference with identical embedder settings and
`--abort-on-bad-builtin-profile-data`; it accepted all 16 profiles without skipping
them. This additional reference avoids treating production's unconditional
exclusions as evidence that a profile was accepted.

Only macOS arm64 is validated. In particular, do not apply an arm64-generated
profile to x64; regenerate and verify it on the intended configuration. Profile
validity must be rechecked after changes to V8, embedder settings, or hardening.

## Reproduce

From the `lib/v8_zig` root, with the production V8 archive already built:

```sh
uv run build-tools/scripts/train-pgo.py \
  .lp-cache/v8-15.8.30 \
  .lp-cache/v8-15.8.30/out/mac-arm64-release-1f90d96e4ec19c97 \
  build-tools/pgo/profiles/15.8.30/mac-arm64
```

Replace the production output path if its configuration hash changes. The tool
copies the production `args.gn`, uses the same `--root=. --dotfile=zig/.gn`, and
changes only the profiling controls: enable counters, clear the input profile,
and disable profile-based reordering. It builds a separate instrumented d8 under
`out/mac-arm64-builtin-pgo-training`, runs `train.js`, and feeds actual counters
through V8's pinned `get_hints.py`. No hashes or counters are rewritten to make
them fit. Only the 16 target builtins' records are selected from the output.

Publication fails if any target did not execute or its hash differs from the
production graph. Raw logs remain in a `run-*` subdirectory of the training
cache. Output files replace atomically, with the manifest digests detecting a
partially updated artifact set. Tiering can change execution counts between
runs, so profiles are not promised to be byte-identical.

For additional strict-reader validation, pass `--strict-reader /path/to/mksnapshot`
from a configuration-matched reference without the permanent exclusion patch.
The tool rejects a reader that prints an explicit exclusion instead of checking
the selected profiles. Normal production exclusions are never changed by this
workflow.

The [hash comparison tool](../scripts/compare-pgo.py) can independently compare
`builtins.profile` with the `production-hashes.txt` retained in the training run:

```sh
uv run build-tools/scripts/compare-pgo.py \
  build-tools/pgo/profiles/15.8.30/mac-arm64/builtins.profile \
  /path/to/training/run/production-hashes.txt \
  --expect-mismatches 0 --expect-absent 0
```

Enabling these profiles or combining them with Google's other entries requires
a separate production configuration change. This workflow only generates and
validates the artifacts requested; it preserves the existing exclusion policy.
