#!/bin/sh
# Borrows checkout and patch paths through process exit. Applies patches in
# order; an error preserves earlier applied patches and reports the failing one.
set -eu
v8=$1
shift
for source in "$@"; do
    patch=$(cd "$(dirname "$source")" && pwd)/$(basename "$source")
    if git -C "$v8" apply --reverse --check "$patch" 2>/dev/null; then
        continue
    fi
    if ! git -C "$v8" apply --check "$patch"; then
        echo "V8 patch does not apply. Rebase $source against the selected V8 version." >&2
        exit 1
    fi
    git -C "$v8" apply "$patch"
done
