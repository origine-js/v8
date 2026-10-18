#!/bin/sh
# Linker driver for Rust crates that link libv8_zig.a with cross-language ThinLTO.
#
# usage (via rustc -Clinker): LTO_CLANG=<clang> LTO_LLD=<ld64.lld|ld.lld> lto-clang.sh <linker args...>
#
# Runs V8's own clang with V8's lld so the ThinLTO bitcode in libv8_zig.a and the
# bitcode rustc embeds (-Clinker-plugin-lto) are optimized together. rustc passes
# GNU-style -plugin-opt flags that Mach-O lld rejects, so they are dropped here;
# lld's defaults (-O2, host CPU) apply instead. Borrows its arguments; links in two passes
# (see below), writing only to the -o path and a scratch directory it removes on exit.
set -eu
clang=${LTO_CLANG:?} lld=${LTO_LLD:?}
for arg in "$@"; do
    shift
    case "$arg" in
        -Wl,-plugin-opt=* | -plugin-opt=*) ;;
        -Wl,-dead_strip) [ -n "${LTO_KEEP_DEAD_STRIP:-}" ] && set -- "$@" "$arg" ;;
        *) set -- "$@" "$arg" ;;
    esac
done

# Two-pass link, because ld64.lld loses the DWARF unwind info of LTO-compiled functions.
# SymbolTable::addDefined gives every prevailing bitcode symbol the *bitcode* file as its owner,
# and ObjFile::registerEhFrames drops any FDE whose function symbol is not owned by the object
# being parsed. So each externally visible function that needs DWARF unwinding (compact encoding
# 0x03000000, common in optimized Rust) ends up with encoding 0 and no FDE, and a panic cannot
# unwind through it: "failed to initiate panic, error 5". Pass 1 runs the LTO and keeps its native
# objects (-save-temps) in a scratch directory; pass 2 links them ahead of the original inputs,
# so the archive members holding the bitcode are never loaded and lld sees ordinary objects.
# LTO_SINGLE_PASS=1 skips this (output without usable panic unwinding through Rust).
out=
prev=
for arg in "$@"; do
    [ "$prev" = -o ] && out=$arg
    prev=$arg
done
if [ -z "$out" ] || [ -n "${LTO_SINGLE_PASS:-}" ]; then
    # shellcheck disable=SC2086
    exec "$clang" --ld-path="$lld" ${LTO_EXTRA_LDFLAGS:-} "$@"
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/lto-clang.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# redirect <out> <args...>: the arguments with the -o operand replaced by <out>.
redirect() {
    to=$1
    shift
    n=$#
    while [ "$n" -gt 0 ]; do
        arg=$1
        shift
        n=$((n - 1))
        if [ "$arg" = -o ] && [ "$n" -gt 0 ]; then
            shift
            n=$((n - 1))
            set -- "$@" -o "$to"
        else
            set -- "$@" "$arg"
        fi
    done
    printf '%s\n' "$@"
}
# Pass 1 arguments are read back one per line (paths here contain no newlines).
redirect "$tmp/out" "$@" > "$tmp/args"
pass1() {
    while IFS= read -r line; do set -- "$@" "$line"; done < "$tmp/args"
    # shellcheck disable=SC2086
    "$clang" --ld-path="$lld" ${LTO_EXTRA_LDFLAGS:-} -Wl,-save-temps "$@"
}
pass1
# Pass 2 inputs: the LTO objects first, then the original arguments minus every bitcode input.
# Bitcode passed as a plain object is loaded eagerly, so it is dropped (its LTO output replaces
# it); archives are replaced by copies that keep only their native members.
here=$(cd "$(dirname "$0")" && pwd)
mkdir "$tmp/ar"
# Search directories for -l<name> archives (paths here contain no newlines).
libdirs=
prev=
for arg in "$@"; do
    case "$arg" in
        -L?*) libdirs="$libdirs
${arg#-L}" ;;
    esac
    [ "$prev" = -L ] && libdirs="$libdirs
$arg"
    prev=$arg
done
n=$#
while [ "$n" -gt 0 ]; do
    arg=$1
    shift
    n=$((n - 1))
    case "$arg" in
        *.o)
            if [ -f "$arg" ]; then
                case $(head -c 4 "$arg" | od -An -tx1 | tr -d ' ') in
                    4243c0de | dec0170b) continue ;; # raw bitcode, bitcode wrapper
                esac
            fi
            ;;
        *.rlib | *.a)
            if [ -f "$arg" ]; then
                arg=$(python3 -I "$here/strip-bitcode-ar.py" "$(dirname "$clang")/llvm-ar" "$tmp/ar/$n" "$arg")
            fi
            ;;
        -l?*)
            # A static library found through -L is replaced by its path when it held bitcode.
            for dir in $libdirs; do
                lib=$dir/lib${arg#-l}.a
                [ -f "$lib" ] || continue
                new=$(python3 -I "$here/strip-bitcode-ar.py" "$(dirname "$clang")/llvm-ar" "$tmp/ar/$n" "$lib")
                [ "$new" = "$lib" ] || arg=$new
                break
            done
            ;;
    esac
    set -- "$@" "$arg"
done
set -- "$tmp"/out*.lto.o "$@"
if [ ! -e "$1" ]; then
    # Nothing was LTO-compiled; pass 1 already produced the output.
    mv "$tmp/out" "$out"
    exit
fi
# shellcheck disable=SC2086
"$clang" --ld-path="$lld" ${LTO_EXTRA_LDFLAGS:-} "$@"
