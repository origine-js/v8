# Rust `v8` crate on libv8_zig.a

`lib/rusty_v8` is a vendored fork of [denoland/rusty_v8](https://github.com/denoland/rusty_v8)
(v152.2.0, V8 15.2.124.1) that links the same `libv8_zig.a` as the Zig modules, so both
languages share one V8 build, one process-wide platform and the same hardened intrinsics.
It never downloads or builds V8.

```sh
zig build rusty                                   # cargo build --release
zig build test-rusty -Drusty_cargo_args="--no-fail-fast"
zig build rusty -Drusty_cargo_args="--example hello_world"
```

`build/rusty.build.zig` runs `build-tools/scripts/cargo-rusty.sh`, which exports what
`lib/rusty_v8/build.rs` consumes (`V8_ZIG_ARCHIVE`, `V8_ZIG_MIMALLOC`, `V8_ZIG_V8_ROOT`,
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
* **Shims rusty needs live in `binding/rusty.cc`**: cppgc, simdutf, Locker/Unlocker, custom
  platform, serializer/deserializer delegates, WasmModuleCompilation, ResourceConstraints,
  `Object::Wrap/Unwrap`, aligned-pointer accessors with tags, ICU time zone. It is a separate
  archive member, so Zig links never pull it in (it calls functions only Rust defines).
  `zig build check-bindings` treats these as expected exports.
* **No Date.** `Date` and `v8__Date__*` are gone from both sides (patch 0003/0005).
* **No v8_inspector/CRDTP yet**: behind the `inspector` cargo feature (off); the C++ shims are not
  ported. ShadowRealm is not installed by the hardened engine.
* **Sandbox is on** (`v8_enable_sandbox`): external ArrayBuffer backing stores and Zig/Rust custom
  allocators are rejected by V8. Origine's errno channel was changed to live in sandbox memory.
* **WebAssembly is on** (`-Dwebassembly=false` to remove). Patch 0007 installs and seals the
  `WebAssembly` namespace like the other intrinsics.
* `v8::V8::attach_initialized(platform)` joins a V8 that Zig's `Engine` already initialized
  (`tests/test_attach.rs`); then neither side initializes or disposes twice.
* Temporal comes from crates.io `temporal_capi`; the Rust build uses `lib_no_temporal`
  (`zig build` still bundles the Zig-side rlibs in `libv8_zig.a`; `v8_no_temporal` is exported as a
  named lazy path).
* Tests that mutate frozen builtins, use Date/ShadowRealm/inspector/CRDTP, or rely on an exact GC
  callback count were adapted or gated.

## Toolchain pin and LTO

`rust-toolchain.toml` pins Rust 1.99 (LLVM 23.1.1; V8's bundled clang is LLVM 23.0.0git). V8 is
built with `-fsplit-lto-unit`, which the cross-language link needs on the Rust side too, so the
script passes `-Zsplit-lto-unit` with `RUSTC_BOOTSTRAP=1`.

`RUSTY_LTO=1` makes rustc emit bitcode (`-Clinker-plugin-lto`) so `ld64.lld` optimizes Rust and V8
together; `hello_world` and most of the suite run. Known problem: `ld64.lld` leaves some LTO-compiled
Rust functions without an unwind entry (compact encoding 0, no FDE), so a panic raised inside the
`v8` crate cannot unwind ("failed to initiate panic, error 5"); plain Rust code unwinds fine. The
default is therefore `RUSTY_LTO=0`: Rust is native code and lld still runs ThinLTO over
`libv8_zig.a`.

## Known gaps

* v8_inspector and CRDTP shims, `Isolate::SetHost*` modules that hardening removes.
* Optimized fast-API calls taking a `void*` trap under the sandbox (`test_fast_calls_pointer` is
  gated).
* Contexts restored from a custom snapshot do not expose `WebAssembly` (the JS-API callbacks that
  `WasmJs::Install` creates are not snapshot external references).
