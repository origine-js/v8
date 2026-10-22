# zig-v8

Builds V8 from official source and provides C bindings and a Zig API. This would be used for embedding the V8 runtime into your Zig or C ABI compatible projects.

V8 is the JavaScript runtime that powers Google Chrome.

## Rust

`rusty_v8/` runs the Rust `v8` crate on this same archive; see [Rust crate on libv8_zig.a](docs/rusty.md).

## Native managed scopes

The managed API provides hardened V8 contexts, explicitly shared capabilities,
backend-independent ESM loading (including asynchronous backends), and optional
per-scope import maps and module maps with update/delete APIs. See [Native V8 scopes](docs/native-scopes.md) for the API,
ownership rules, implementation checkpoints, and isolation limits.

This directory is the local `v8` Zig package used by origine. The application
entry point is `../../src/main.zig`; build and run the REPL from `../..`:

```sh
zig build
zig build run
zig build -Doptimize=small
```

Within this package, `zig build` installs native libraries and `zig build test`
runs package tests. Import-map isolation and shared private capabilities are
exercised in those tests. To reuse an archive, pass
`-Dprebuilt_v8_path=/absolute/path/libv8_zig.a`.

## Zig modules and source layout

The build exports separate `@v8` (raw wrappers), `@util` (typed value constructors and allocator), and `@mimalloc`
(allocator) modules. Add the modules
you use to your root module with `root.addImport(name, dependency.module(name))`;
their transitive dependencies share the same raw V8 types. `@diagnostics` exposes
optional startup tracing for applications that need it.

Declare `.v8 = .{ .path = "lib/v8_zig" }` in the application's `build.zig.zon`,
then call `b.dependency("v8", .{ .target = target, .optimize = optimize })`.
Modules link their native dependencies by default, including cached Darwin
bitcode conversion. External final linkers can pass `.link_native = false`,
then use `dependency.namedLazyPath("v8")`, `dependency.namedLazyPath("clang_bin")`,
and `dependency.artifact("mimalloc")` to obtain the original archive, matching
LLVM tools, and mimalloc library. These paths and modules are build-owned.

```zig
const Engine = @import("@engine").Engine;
const managed = @import("@managed");
const eu = @import("@util");
const alloc = eu.alloc;
var engine = Engine.init(.{});
defer engine.deinit();
const rt = try managed.Runtime.create(alloc, .{});
defer rt.destroy();
const scope = try rt.createScope(.{});
const value = try scope.eval("1 + 2", "app:/entry.js", null);
defer value.deinit();
```

Initialize one engine per process. Destroy all runtimes, isolates and owned handles
before engine teardown; V8 cannot be initialized again after disposal. Raw users
may still manage platform initialization themselves instead of using `Engine`.

Source responsibilities are grouped under `v8/`, `generated/`,
`memory/`, `diagnostics/`, and `tests/`. Generated files remain committed;
edit their generator or source manifests and regenerate rather than editing outputs.
`@engine` (process lifecycle) and `@managed` (runtimes and scopes) now live in origine's `src/`.
From origine, `V8_STARTUP_TRACE=1 zig build run` reports engine, runtime and scope startup stages.

## Typed value constructors

`const eu = @import("@util"); const v = eu.v;` provides typed local constructors such as
`v.num_u32(isolate, 42)`, `v.array(isolate, 3)`, and
`v.str_utf8(isolate, "hello")`. The returned types are `v8.Number`, `v8.Array`,
`v8.String`, and the corresponding raw wrappers. Run on the entered isolate
thread with a live handle scope; local handles expire when that scope closes.
The helpers preserve the raw constructors' optional results and failure behavior.

`eu.alloc` exposes the thread-safe, process-lifetime mimalloc allocator. Free
caller-owned allocations through `eu.alloc`; the allocator needs no deinit.

Copying string helpers have `_internalized` pairs, selecting V8's `.Internalized`
creation mode instead of `.Normal`. `str_one_byte` uses Latin-1 bytes;
`str_two_byte` uses UTF-16 code units. Inputs to copying constructors are borrowed
only through return. `str_external_one_byte` and `str_external_two_byte` borrow
immutable backing storage through isolate disposal and never free it. Their
`_internalized` pairs create an external string and canonicalize it; V8 may return
an existing canonical string that is not external.

The namespace also includes `boolean`, `null_value`, `undefined_value`, BigInt,
symbol/private registry helpers, array buffers (including shared stores),
`promise_resolver`, and `err`/`type_error`/`range_error`/`reference_error`/
`syntax_error`. Error helpers construct exception values without throwing them.

## Allocators

The Zig build compiles pinned mimalloc 3.5.3 into `libmimalloc.a` and links it into
the exported V8 module, tests, and shell. It uses the `mi_*` interface without
overriding libc allocation functions. the `@mimalloc` module exposes a thread-safe
`std.mem.Allocator` plus the raw `mi_*` and heap bindings; the shell uses it for
ArrayBuffer backing stores. `build-tools/patches/v8/0004-mimalloc.patch` also routes V8's
`base::Malloc/Calloc/Realloc/Free/AlignedAlloc` (zones, traced handles, value-serializer
buffers, `Malloced`) to mimalloc via weak `mi_*` references, so tools linked without
mimalloc (mksnapshot) fall back to libc.

```zig
const mimalloc = @import("@mimalloc");
const rt = try m.Runtime.create(metadata_alloc, .{
    .array_buffer_allocator = .{ .zig = mimalloc.allocator },
});
defer rt.destroy();
```

Any thread-safe Zig allocator works with `v8.ArrayBuffer.Allocator.fromZig`.
The default options retain V8's default backing-store allocator.
See [allocator ownership and limits](docs/native-scopes.md#allocators) for borrowed
allocators, retained backing stores, and sandbox requirements.

## System Requirements
- Zig 0.17.0. Download from https://ziglang.org/download/.
- Python 3 and uv (runs the pinned ICU compression script dependencies)
- unzip
- rsync
- For native macOS builds:
  - XCode (You won't need this when using zig's c++ toolchain!)<br/>
if you come across this error:<br />
`xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`<br />
  run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## Build
Compiling v8 will take 20+ minutes.

A fresh clone downloads the pinned packages in `build.zig.zon`, then bootstraps
depot_tools and fetches V8 15.8.30 and its dependencies over HTTPS. Git and
network access to GitHub, pkg.lightpanda.io, and Chromium's source and toolchain
download servers are required. No private repository credentials are required.
The depot_tools pin matches V8 15.8.30's `DEPS`. The build retains the full ICU
backend for its compressed ICU provider and locale API instead of V8's ICU4X default.
Release desktop builds enable builtin PGO with Google's matching `15.8.30.0`
baseline. The downloader verifies the upstream source revision and records a
SHA-256 receipt. Sixteen builtin profiles are explicitly excluded regardless of
whether their hashes match; V8 checks hashes for the remaining entries and warns
when it discards a mismatch. Matching entries guide builtin branch optimization;
profile-based builtin reordering is disabled. See [builtin PGO](docs/builtin-pgo.md)
for the exclusions, measured acceptance, and verification commands.
Arm64 uses Google's x64 profile, as supported by V8. Profiles are downloaded into
the local V8 cache and are never modified or committed. Debug V8 disables PGO.
Use `-Dbuiltin_pgo=false` for an unprofiled comparison build; different settings
use separate output directories. This configures builtin PGO, not C++ compiler PGO.
The first build applies the committed patches in `build-tools/patches/` automatically;
`zig build build-v8` re-applies them and rebuilds V8.
Keep `zig-pkg/`, `.lp-cache/`, `.zig-cache/`, and `zig-out/` local; they are
download/build caches and must not be committed.

```sh
zig build                    # release V8 (default)
zig build build-v8           # rebuild V8 after changing it or its patches; plain builds reuse the archive
zig build build-v8 -Dv8_debug=true  # debug V8: quicker incremental compiles while changing V8
zig build patch-v8           # fetch V8 and apply patches only
```

Release V8 is the default everywhere, independent of `-Doptimize`, which only affects
Zig code. Debug and release V8 use separate build directories. `just dev`, `just patch`
and `just new-patch <series> <name>` wrap the V8-development loop; see
[build-tools/README.md](build-tools/README.md).

V8 15.8 requires GN to place the macOS SDK inside the build directory, so GN selects the SDK itself
(the active Xcode / Command Line Tools) and links it there. Do not pass an absolute `-Dmac_sdk_path`
pointing outside the build directory: GN rejects it (`File is not inside output directory`). To build
against a different SDK, switch it with `xcode-select` or `DEVELOPER_DIR`.

Once complete, you can find v8 in: `zig-out/libv8_zig.a`

The library embeds the complete ICU data package compressed with zstd 1.5.7.
The C binding expands it once, before V8 initialization, into aligned immutable
storage retained until process exit. No external `icudtl.dat` is required at
runtime, and all bundled locales/features are preserved. This trades startup
decompression and expanded heap storage for a smaller executable. The build-time
snapshot generator still uses an uncompressed data file in the V8 output directory.
The build runs `build-tools/scripts/compress-icu.py` through uv to generate the embedded
frame; the library includes only the zstd decoder, not its compressor.
Zig builds that decoder with `.small` optimization and stripped debug information,
then flattens it into `libv8_zig.a`; consumers need no additional zstd link flag.
`zig build build-zstd` builds the decoder alone and installs it as
`zig-out/lib/libzstd_decoder.a` for inspection.

## Original builtin references

`v8.Intrinsics.get(context, "ArrayPrototypePush")` retrieves original builtin
method references from a private, snapshotted native-context table. See
[Original builtin references](docs/intrinsics.md) for supported entries, the trust
boundary, and maintenance of the versioned V8 Git patch.

## Generated bindings
`zig build gen` asks V8's own clang (with the exact flags used for `binding.cc`) and regenerates, in place:

| Output | Source of truth | Purpose |
| --- | --- | --- |
| `src/generated/binding.zig` | `build-tools/bindgen/layout.zon` | struct sizes / constants read by Zig |
| `binding/layout.gen.h` | `build-tools/bindgen/layout.zon` | `static_assert`s: a V8 upgrade breaks the C++ build until you re-run `gen` |
| `src/generated/externs.gen.zig` | `binding/binding.cc` + `build-tools/bindgen/typemap.zon` | an ABI-exact `extern fn` for every `v8__*` shim |

The outputs are committed. Run `gen` after changing `layout.zon`, `typemap.zon`, `binding.cc` or upgrading V8.
Types the generator cannot map with certainty are listed at the end of `externs.gen.zig`; add an entry to `typemap.zon` to enable them.

### Keeping them honest
| Step | What it checks |
| --- | --- |
| `zig build check-generated` | the committed generated files equal a fresh run (use it in CI) |
| `zig build check-bindings` | the library's exported `v8__*` symbols equal the declared externs (hard failure), then reports which shims `v8.zig` does not wrap yet and which shims [rusty_v8](https://github.com/denoland/rusty_v8) has that this repo lacks (a porting checklist; the dependency is pinned in `build.zig.zon` and only fetched by this step) |

## Tests
`zig build test` runs `src/tests.zig` and the behavior groups under `src/tests/`: behavioural tests for each wrapper in `v8.zig` against a real V8
(values, objects, functions and callbacks, templates, promises, errors and stack traces, termination, host
callbacks), plus checks that the Zig struct sizes equal the C++ ones. A fresh isolate and context is created per
test; the V8 platform is shared because it can only be initialised once per process.
