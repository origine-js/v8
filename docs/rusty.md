# Rust `v8` crate on libv8_zig.a

`rusty_v8` is a vendored fork of [denoland/rusty_v8](https://github.com/denoland/rusty_v8)
(local version 158.0.0, V8 15.8.30) that links the same `libv8_zig.a` as the Zig modules, so both
languages share one V8 build, one process-wide platform and the same hardened intrinsics.
It never downloads or builds V8.
The lazy `rusty_v8` dependency in `build.zig.zon` is only the upstream 152.2.0
porting checklist used by `check-bindings`; it does not select the runtime or
replace this vendored 158.0.0 fork.

```sh
zig build rusty                                   # cargo build --release
zig build test-rusty -Drusty_cargo_args="--no-fail-fast"
zig build rusty -Drusty_cargo_args="--example hello_world"
```

`build/rusty.build.zig` runs `build-tools/scripts/cargo-rusty.sh`, which exports what
`rusty_v8/build.rs` consumes (`V8_ZIG_ARCHIVE`, `V8_ZIG_MIMALLOC`, `V8_ZIG_V8_ROOT`,
`V8_ZIG_BINDING`, `V8_ZIG_GN_OUT`), checks that Rust's LLVM is not newer than V8's clang, and
links with V8's own `ld64.lld` through `lto-clang.sh`. `build.rs` runs bindgen over
`binding/binding.hpp` with the defines GN used for `binding.cc`, so struct layouts always match
the archive. bindgen needs libclang >= 21.1 (`LIBCLANG_PATH`; the script falls back to the
Command Line Tools).

## What changed compared to upstream rusty_v8

* **ABI follows libv8_zig.** `extern "C"` blocks were adapted to the shims in `binding.cc`:
  `String::Write*`/`Utf8Length` (`size_t`), `NewExternalOneByte` (`int` length),
  `Function::GetScriptOrigin` (heap copy + `v8__ScriptOrigin__DELETE`), default global template
  (`v8__ObjectTemplate__New__DEFAULT`; hardened contexts always need one).
* **Shims rusty needs live in `binding/rusty.cc`**: cppgc, Locker/Unlocker, custom
  platform, serializer/deserializer delegates, WasmModuleCompilation, ResourceConstraints,
  `Object::Wrap/Unwrap`, aligned-pointer accessors with tags, ICU time zone. It is a separate
  archive member, so Zig links never pull it in (it calls functions only Rust defines).
  `zig build check-bindings` treats these as expected exports.
* **simdutf shims (`simdutf__*`) live in `binding/binding.cc`**, shared with Zig. `bindgen` generates their
  externs like the `v8__*` ones (`simdutf__result` is mapped in `typemap.zon`), and `src/v8/simdutf.zig` calls them.
* **No Date.** `Date` and `v8__Date__*` are gone from both sides (patch 0003/0005).
* **v8_inspector and CRDTP** are behind the `inspector` cargo feature (off by default; V8's inspector
  is always inside `libv8_zig.a`). Their shims (`v8_inspector__*`, `crdtp__*`, from upstream
  `binding.cc` and `crdtp_binding.cc`) live at the end of `binding/rusty.cc`. The functions Rust
  defines (`*__BASE__*`, `crdtp__FallthroughCallback__*`) are declared `__attribute__((weak))`, so a Rust
  build without the `inspector` feature still links. The generated `deno_inspector` protocol
  domains are not built.
  ShadowRealm is not installed by the hardened engine.
  `zig build test-rusty -Drusty_cargo_args="--features inspector --no-fail-fast"` runs the
  `inspector_tests` and `crdtp_tests` modules.
* **Sandbox is on** (`v8_enable_sandbox`): external ArrayBuffer backing stores and Zig/Rust custom
  allocators are rejected by V8. Origine's errno channel was changed to live in sandbox memory.
* **WebAssembly is on** (`-Dwebassembly=false` to remove). Patch 0007 installs and seals the
  `WebAssembly` namespace like the other intrinsics.
* `v8::V8::attach_initialized(platform)` joins a V8 that Zig's `Engine` already initialized
  (`rusty_v8/tests/test_attach.rs`); then neither side initializes or disposes twice.
* Temporal comes from crates.io `temporal_capi`; the Rust build uses `lib_no_temporal`
  (`zig build` still bundles the Zig-side rlibs in `libv8_zig.a`; `v8_no_temporal` is exported as a
  named lazy path).
* Tests that mutate frozen builtins, use Date/ShadowRealm, or rely on an exact GC
  callback count were adapted or gated.

## Toolchain pin and LTO

`rust-toolchain.toml` pins Rust 1.99 (LLVM 23.1.1; V8's bundled clang is LLVM 24.0.0git). V8 is
built with `-fsplit-lto-unit`, which the cross-language link needs on the Rust side too, so the
script passes `-Zsplit-lto-unit` with `RUSTC_BOOTSTRAP=1`.

`RUSTY_LTO=1` (the default) makes rustc emit bitcode (`-Clinker-plugin-lto`) so `ld64.lld` optimizes
Rust and V8 together; `RUSTY_LTO=0` compiles Rust to native code and lld only runs ThinLTO over
`libv8_zig.a`.

`lto-clang.sh` links in two passes because of an `ld64.lld` bug. lld gives every prevailing bitcode
symbol the *bitcode* file as its owner (`SymbolTable::addDefined`), and `ObjFile::registerEhFrames`
drops the FDE of any function whose symbol is not owned by the object being parsed. A function that
LLVM cannot describe with compact unwind (DWARF mode `0x03000000`: epilogues with
`remember_state`, common in optimized Rust) and that stays externally visible after ThinLTO
(`.llvm.NNN` promoted locals are fine) therefore ends up with encoding 0 and no FDE, and a panic
inside the `v8` crate aborts with "failed to initiate panic, error 5". Pass 1 runs the LTO with
`-save-temps` into a scratch directory; pass 2 links the resulting native objects instead of the
bitcode (bitcode objects are dropped; `strip-bitcode-ar.py` hands lld archive copies with only
their native members). `LTO_SINGLE_PASS=1` skips pass 2 to reproduce the bug.

## Known gaps

* `Isolate::SetHost*` modules that hardening removes.
* Optimized fast-API calls taking a `void*` trap under the sandbox (`test_fast_calls_pointer` is
  gated).
* Contexts restored from a custom snapshot do not expose `WebAssembly` (the JS-API callbacks that
  `WasmJs::Install` creates are not snapshot external references).

## Cargo profiles

* `dev`: `opt-level = 1`, line-tables-only debug info (none for dependencies), incremental,
  256 codegen units, `panic = "unwind"`.
* `release`: `codegen-units = 1`, `panic = "abort"`, debug info stripped. Panics abort, so run
  `should_panic` / `catch_unwind` tests in the dev/test profile.
