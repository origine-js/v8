# zig-v8

Builds V8 from official source and provides C bindings and a Zig API. This would be used for embedding the V8 runtime into your Zig or C ABI compatible projects.

V8 is the JavaScript runtime that powers Google Chrome.

## System Requirements
- Zig 0.17.0. Download from https://ziglang.org/download/.
- Python 3 (2.7 seems to work as well)
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

If V8 fails to compile against your newest macOS SDK (e.g. ICU: `use of undeclared identifier 'NAN'`), point it at an older one with
`-Dmac_sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.

Once complete, you can find v8 in: `zig-out/libv8_zig.a`

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
