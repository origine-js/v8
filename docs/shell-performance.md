# Shell size and startup measurements

Measured on macOS arm64, 2026-10-14, Zig 0.17.0. The shell was built with
`just build-shell_darwin release` (`-O small`) against the installed V8 and
mimalloc archives. These results describe those installed artifacts; the V8
archive was not rebuilt for this investigation.

## Binary size

The instrumented executable is 53,468,808 bytes (50.99 MiB).

| Contribution | MiB | Method |
| --- | ---: | --- |
| Executable `__text` | 24.35 | Mach-O section size |
| Read-only `__TEXT,__const` | 11.47 | Mach-O section size |
| `__LINKEDIT` metadata | 13.63 | Mach-O segment size |
| ICU data, within read-only constants | 10.32 | Symbol address span |
| V8 snapshot, within read-only constants | 0.33 | Symbol address span |
| V8 C++ code, within executable text | 19.77 | Namespace/address attribution |
| V8 embedded builtins, within executable text | 1.97 | Blob address range |
| ICU code, within executable text | 1.36 | Namespace/address attribution |

Rows overlap: blob and code estimates are subdivisions of the section totals.
Mach-O `llvm-nm --print-size` returns zero sizes, so symbol estimates use the
distance to the next distinct symbol address. They include alignment and can
include unnamed bytes; aliases are deduplicated. They are not exact object-file
or source-file attribution. `__PAGEZERO` reserves virtual address space and
contributes no file bytes; zero-fill BSS likewise is not disk payload.

A temporary copy stripped with `/usr/bin/strip -S -x` was 39,647,392 bytes
(37.81 MiB): a saving of 13,821,416 bytes (13.18 MiB, 25.85%). The original
executable was preserved. Stripping is a distribution-size opportunity; this
experiment does not establish a startup improvement or validate the stripped
copy's signing/distribution behavior.

The largest ordinary function address spans include Turboshaft
`GraphBuilder::Process` (~108 KiB), `BytecodeAnalysisImpl::Analyze` (~107 KiB),
and `CodeGenerator::AssembleArchInstruction` (~77 KiB). No single ordinary
function dominates the executable; V8's engine/compiler code and ICU dominate.

Reproduce the section and symbol inspection with:

```sh
llvm-size --format=darwin -l zig-out/shell
llvm-nm -n --demangle zig-out/shell
```

## Startup

Enable instrumentation with `V8_STARTUP_TRACE=1`. The shell buffers stage
measurements, and scope creation buffers finer measurements on its calling
thread; both print to stderr after initialization. Normal execution prints no
timing report. Timestamps use the monotonic clock. Scope-detail stages are
nested inside the shell's scope stages and must not be added to the total.

Thirty measured runs after three warmups, stdin at EOF:

| Initialization stage | Median ms |
| --- | ---: |
| Host allocator/I/O setup | 0.004 |
| Platform creation | 0.136 |
| V8 initialization | 0.406 |
| Runtime/isolate creation | 0.597 |
| Import maps | 0.068 |
| First scope | 9.546 |
| Second scope | 1.135 |
| Counter/capabilities | 0.239 |
| Module imports and pump | 0.100 |
| Total initialization | 12.227 |

Stage medians are computed independently and need not sum to the total median.
Total initialization ranged from 11.959 to 12.605 ms. The first single trace
was slower (19.797 ms), illustrating first-run/cache variability.

The first scope divides into context creation (0.298 ms), host setup (0.004 ms),
bootstrap compilation (0.258 ms), bootstrap execution/hardening (8.975 ms), and
finalization (0.001 ms). The second bootstrap execution takes only 0.772 ms.

### Controlled Segmenter experiment

Temporarily removed only the `Intl.Segmenter` root-discovery block in
`src/managed/bootstrap.js`, rebuilt the shell, and repeated the same 30-run
measurement. Initialization fell to 4.289 ms (range 4.099–4.567 ms); first-scope
bootstrap execution fell to 0.991 ms. The original source and instrumented
binary were restored after the experiment.

This isolates about **7.94 ms** to that block and the work it triggers. The
first-versus-second scope difference is consistent with process-wide lazy
ICU/locale/segmentation initialization. The experiment identifies the triggering
block; it does not distinguish individual ICU internal routines.

Removing the block is not a proposed production fix: it discovers additional
intrinsic prototypes needed by the hardener. Any optimization must preserve
that coverage. Investigating reuse/snapshotting of a hardened context or more
direct prototype discovery is a possible next step, with isolation tests.

### Timing boundaries

Instrumentation starts inside `main` and ends before the banner/REPL. It
excludes process launch, dynamic loader work, banner output, and teardown.
The measurement script's traced full-process median was 20.654 ms, including
these other costs and reporting. Separately, an untraced Hyperfine run measured
22.5 ± 0.7 ms mean (21.0–23.7 ms), including full process lifetime. Neither is
directly interchangeable with an unspecified 16 ms startup measurement.
The difference between process time and internal initialization cannot be
attributed solely to the loader.

Reproduce:

```sh
just build-shell_darwin release
V8_STARTUP_TRACE=1 zig-out/shell </dev/null
uv run build-tools/measure-startup.py
hyperfine --warmup 3 --runs 30 'zig-out/shell </dev/null'
```

Raw local artifacts are `zig-out/startup-measurements.json`,
`zig-out/startup-no-segmenter.json`, `zig-out/process-benchmark.json`, and
`zig-out/size-analysis.json.txt`. These live in the ignored build-output directory.

### Engine intrinsic finalization

The engine now reads hidden prototypes directly from native-context roots,
freezes its intrinsic graph, and locks ECMAScript global bindings before returning
application contexts. The managed bootstrap receives the retained graph and
unsupported iterator prototypes through private initializer arguments; it no
longer constructs instances for discovery or freezes builtins itself.

After rebuilding V8 and the release shell, 30 warm runs with three warmups gave:

| Stage | Median ms |
| --- | ---: |
| V8 initialization, including compressed ICU setup | 11.537 |
| First context creation and engine finalization | 0.519 |
| First bootstrap compilation | 0.110 |
| First bootstrap execution | 0.098 |
| First complete managed scope | 0.740 |
| Second complete managed scope | 0.511 |
| Total initialization | 13.817 |
| Full traced process lifetime | 20.720 |

Raw samples are in `zig-out/startup-engine-hardening.json`. The historical
Segmenter experiment above used a different ICU setup and cannot establish a
total-startup speedup for this build. Concurrent workspace builds also replaced
the shell before a baseline copy was saved: that copy already contains the new
intrinsic inventory API. Its timings are not a pre-change baseline. The current
measurement confirms the discovery cost is absent from bootstrap execution;
V8/ICU initialization is now the dominant measured stage.

### Deferred ICU decompression

ICU package expansion now happens at the first common-data lookup, rather than
inside V8 initialization. A fresh-process test verifies that V8 initialization,
provider registration, context creation, and plain JS leave it compressed. Four
concurrent first-use Intl requests verify multilingual behavior and safe shared
publication. The whole package expands once and remains immutable until exit.

A saved eager-loading release shell and the rebuilt lazy-loading shell were
measured consecutively, each with three warmups and 30 warm runs:

| Stage | Eager median ms | Lazy median ms |
| --- | ---: | ---: |
| V8 initialization | 11.886 | 0.353 |
| First complete managed scope | 0.740 | 0.757 |
| Total initialization | 14.092 | 2.608 |
| Full traced process lifetime | 21.171 | 9.171 |

The expansion cost moves to the first operation that needs ICU data; it is
not eliminated. Raw samples are `zig-out/startup-eager-icu-baseline.json` and
`zig-out/startup-lazy-icu.json`. Reproduce loading verification with
`zig build test-icu-lazy` and the usual SDK/optimization options.
