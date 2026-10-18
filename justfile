default:
    @just --list

# Library with release V8 (patches apply automatically).
build:
    zig build

# Working on V8 or its patches: debug V8 for quick incremental compiles.
dev:
    zig build -Dv8_debug=true

# Fetch V8 and apply patches only, then edit .lp-cache/v8-*/ and run `just new-patch`.
patch:
    zig build patch-v8

# Turn edits in a patched checkout into the next patch of a series (v8, icu, partition_alloc).
new-patch series name *new_files:
    sh build-tools/scripts/new-patch.sh {{ if series == "v8" { ".lp-cache/v8-15.2.124.1" } else { ".lp-cache/v8-15.2.124.1/third_party/" + series } }} build-tools/patches/{{series}} {{name}} {{new_files}}

test:
    zig build test

# Tests against debug V8.
test-dev:
    zig build test -Dv8_debug=true
