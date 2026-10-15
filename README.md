# zig-v8

Builds V8 from official source and provides C bindings and a Zig API. This would be used for embedding the V8 runtime into your Zig or C ABI compatible projects.

V8 is the JavaScript runtime that powers Google Chrome.

## Native managed scopes

The managed API provides hardened V8 contexts, explicitly shared capabilities,
backend-independent ESM loading (including asynchronous backends), and optional
per-scope import maps and module maps with update/delete APIs. See [Native V8 scopes](docs/native-scopes.md) for the API,
ownership rules, implementation checkpoints, and isolation limits.

`zig build shell` demonstrates two scopes with different import maps over an in-memory backend
and a shared counter with private state. Switch scopes with `:a` and `:b`.

## Allocators

The Zig build compiles pinned mimalloc 3.5.3 into `libmimalloc.a` and links it into
the exported V8 module, tests, and shell. It uses the `mi_*` interface without
overriding libc allocation functions. `mimalloc.zig` exposes a thread-safe
`std.mem.Allocator`; the shell uses it for ArrayBuffer backing stores.

```zig
const mimalloc = @import("mimalloc.zig");
var rt = try m.Runtime.initWithOptions(metadata_alloc, .{
    .array_buffer_allocator = .{ .zig = mimalloc.allocator },
});
defer rt.deinit();
```

Any thread-safe Zig allocator works with `v8.ArrayBuffer.Allocator.fromZig`.
The existing `Runtime.init` retains V8's default backing-store allocator.
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

```sh
zig build
```

V8 15.2 requires GN to place the macOS SDK inside the build directory, so GN selects the SDK itself
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
The build runs `build-tools/compress-icu.py` through uv to generate the embedded
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
| `src/binding.zig` | `build-tools/layout.zon` | struct sizes / constants read by Zig |
| `binding/layout.gen.h` | `build-tools/layout.zon` | `static_assert`s: a V8 upgrade breaks the C++ build until you re-run `gen` |
| `src/externs.gen.zig` | `binding/binding.cc` + `build-tools/typemap.zon` | an ABI-exact `extern fn` for every `v8__*` shim |

The outputs are committed. Run `gen` after changing `layout.zon`, `typemap.zon`, `binding.cc` or upgrading V8.
Types the generator cannot map with certainty are listed at the end of `externs.gen.zig`; add an entry to `typemap.zon` to enable them.

### Keeping them honest
| Step | What it checks |
| --- | --- |
| `zig build check-generated` | the committed generated files equal a fresh run (use it in CI) |
| `zig build check-bindings` | the library's exported `v8__*` symbols equal the declared externs (hard failure), then reports which shims `v8.zig` does not wrap yet and which shims [rusty_v8](https://github.com/denoland/rusty_v8) has that this repo lacks (a porting checklist; the dependency is pinned in `build.zig.zon` and only fetched by this step) |

## Tests
`zig build test` runs `src/test.zig`: behavioural tests for each wrapper in `v8.zig` against a real V8
(values, objects, functions and callbacks, templates, promises, errors and stack traces, termination, host
callbacks), plus checks that the Zig struct sizes equal the C++ ones. A fresh isolate and context is created per
test; the V8 platform is shared because it can only be initialised once per process.
