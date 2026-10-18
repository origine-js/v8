#!/bin/sh
# Linker driver for Rust crates that link libv8_zig.a with cross-language ThinLTO.
#
# usage (via rustc -Clinker): LTO_CLANG=<clang> LTO_LLD=<ld64.lld|ld.lld> lto-clang.sh <linker args...>
#
# Runs V8's own clang with V8's lld so the ThinLTO bitcode in libv8_zig.a and the
# bitcode rustc embeds (-Clinker-plugin-lto) are optimized together. rustc passes
# GNU-style -plugin-opt flags that Mach-O lld rejects, so they are dropped here;
# lld's defaults (-O2, host CPU) apply instead. Borrows its arguments; exec()s clang.
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
# shellcheck disable=SC2086
exec "$clang" --ld-path="$lld" ${LTO_EXTRA_LDFLAGS:-} "$@"
