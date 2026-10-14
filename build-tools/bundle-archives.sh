#!/bin/sh
# Borrows the executable/input paths through this process; creates a build-owned
# output archive, flattening members so consumers need only -lv8_zig. Inputs are
# unchanged; on archiver failure the build owns any partially generated output.
set -eu
zig=$1
output=$2
shift 2
{
    printf 'CREATE "%s"\n' "$output"
    for archive do
        printf 'ADDLIB "%s"\n' "$archive"
    done
    printf 'SAVE\nEND\n'
} | "$zig" ar -M
