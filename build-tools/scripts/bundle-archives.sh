#!/bin/sh
# Usage: bundle-archives.sh <ar-tool> <subcommand|-> <output> [--rust <ninja> <build-dir> <target>] <inputs...>.
# With --rust, also flattens the target-side Rust rlibs (Temporal's temporal_capi and
# the Rust std it needs): GN's alink rule drops them from complete static libraries, so
# they are listed through `ninja -t inputs` and added as archive members (rlib metadata
# members are ignored by linkers). Borrows the tool/input paths through this process; creates a build-owned
# output archive, flattening members so consumers need only -lv8_zig. Inputs are
# unchanged; on archiver failure the build owns any partially generated output.
set -eu
ar=$1
sub=$2
output=$3
shift 3
rlibs=
if [ "${1:-}" = --rust ]; then
    ninja=$2 build_dir=$3 target=$4
    shift 4
    rlibs=$(cd "$build_dir" && "$ninja" -t inputs "$target" | grep '\.rlib$' | grep -v '^clang_arm64_for_rust_host' | sed "s|^|$build_dir/|")
fi
{
    printf 'CREATE "%s"\n' "$output"
    for rlib in $rlibs; do
        printf 'ADDLIB "%s"\n' "$rlib"
    done
    for archive do
        printf 'ADDLIB "%s"\n' "$archive"
    done
    printf 'SAVE\nEND\n'
} | if [ "$sub" = - ]; then "$ar" -M; else "$ar" "$sub" -M; fi
