#!/bin/sh
# Runs cargo for rusty_v8 against the libv8_zig.a built by this repository.
#
# usage: cargo-rusty.sh <rusty_v8_dir> <archive> <mimalloc> <v8_root> <gn_out> <binding_dir> <clang_bin> <cargo args...>
#
# Reads the paths, borrows them for the duration of the cargo run, writes only
# under <rusty_v8_dir>/target. Exports the V8_ZIG_* variables rusty_v8/build.rs
# expects, and links with V8's own clang/lld so Rust bitcode (linker-plugin LTO)
# and the ThinLTO bitcode inside libv8_zig.a are optimized together.
set -eu
# Zig passes cache paths relative to the invocation directory; cargo runs elsewhere.
abs() { case $1 in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
dir=$(abs "$1") archive=$(abs "$2") mimalloc=$(abs "$3") root=$(abs "$4")
gn_out=$(abs "$5") binding=$(abs "$6") clang_bin=$(abs "$7")
shift 7

export V8_ZIG_ARCHIVE="$archive"
export V8_ZIG_MIMALLOC="$mimalloc"
export V8_ZIG_V8_ROOT="$root"
export V8_ZIG_GN_OUT="$gn_out"
export V8_ZIG_BINDING="$binding"

# bindgen needs libclang >= 21.1; V8's clang bundle does not ship one.
if [ -z "${LIBCLANG_PATH:-}" ] && [ -d /Library/Developer/CommandLineTools/usr/lib ]; then
    export LIBCLANG_PATH=/Library/Developer/CommandLineTools/usr/lib
fi

llvm_major() { "$1" --version | sed -n 's/.*clang version \([0-9][0-9]*\).*/\1/p' | head -n1; }
rustc_llvm=$(cd "$dir" && rustc -vV | sed -n 's/^LLVM version: \([0-9][0-9]*\).*/\1/p')
clang_llvm=$(llvm_major "$clang_bin/clang")
# RUSTY_LTO=1 (default): rustc emits bitcode and V8's lld optimizes Rust and libv8_zig.a together.
# lto-clang.sh links in two passes to work around ld64.lld dropping the DWARF unwind info of
# LTO-compiled functions (see there). RUSTY_LTO=0: Rust is compiled to native objects; lld still
# runs ThinLTO over the bitcode inside libv8_zig.a (no cross-language inlining).
if [ "${RUSTY_LTO:-1}" = 1 ] && [ "$rustc_llvm" -gt "$clang_llvm" ]; then
    echo "cargo-rusty: rustc uses LLVM $rustc_llvm but V8's clang is LLVM $clang_llvm;" >&2
    echo "cargo-rusty: its bitcode cannot be read by V8's lld. Pin an older Rust" >&2
    echo "cargo-rusty: toolchain or set RUSTY_LTO=0." >&2
    exit 1
fi
here=$(cd "$(dirname "$0")" && pwd)
host=$(cd "$dir" && rustc -vV | sed -n 's/^host: //p')
case "$host" in
    *-apple-*) lld=$clang_bin/ld64.lld ;;
    *) lld=$clang_bin/ld.lld ;;
esac
# A per-target linker keeps build scripts and proc macros on the host toolchain:
# --target stops RUSTFLAGS from applying to them.
if [ "${RUSTY_LTO:-1}" = 1 ]; then
    # V8 is built with -fsplit-lto-unit (+ whole-program vtables), so Rust must set the same
    # module flag or lld rejects the mix. -Zsplit-lto-unit is unstable; RUSTC_BOOTSTRAP lets
    # the pinned stable toolchain accept it (what Chromium's own Rust toolchain does).
    export RUSTC_BOOTSTRAP=1
    sep=$(printf '\037')
    export CARGO_ENCODED_RUSTFLAGS="-Clinker-plugin-lto${sep}-Cembed-bitcode=yes${sep}-Zsplit-lto-unit${sep}-Cforce-unwind-tables=yes"
fi
triple_env=$(printf '%s' "$host" | tr 'a-z-' 'A-Z_')
eval "export CARGO_TARGET_${triple_env}_LINKER=\"$here/lto-clang.sh\""
export LTO_CLANG="$clang_bin/clang" LTO_LLD="$lld"
cd "$dir"
sub=$1
shift
exec cargo "$sub" --target "$host" "$@"
