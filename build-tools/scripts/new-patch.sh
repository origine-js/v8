#!/bin/sh
# Writes your edits to a patched checkout as the next patch in a series.
#
# usage: new-patch.sh <checkout> <series-dir> <name> [new-file...]
#
# Run the build (or apply-patches.sh) first so the checkout holds the whole series,
# then edit the checkout and run this. Output: <series-dir>/NNNN-<name>.patch, the
# diff against the series-applied baseline. Pass paths of files you created, since
# git only diffs tracked files. The edits are then reverted in the checkout so the next
# build applies the new patch through the series.
set -eu

checkout=$(cd "$1" && pwd)
series=$(cd "$2" && pwd)
name=$3
shift 3
state=$checkout/.zig-patches
[ -f "$state/index" ] || { echo "No baseline in $state; run apply-patches.sh first." >&2; exit 1; }

last=$(ls "$series"/*.patch 2>/dev/null | sed 's|.*/\([0-9]*\)-.*|\1|' | sort | tail -n 1)
next=$(printf '%04d' $((${last:-0} + 1)))
out=$series/$next-$name.patch

export GIT_INDEX_FILE=$state/index
for f in "$@"; do git -C "$checkout" add -N -f -- "$f"; done
git -C "$checkout" diff --binary >"$out"
[ -s "$out" ] || { rm -f "$out"; echo "No changes against the series baseline." >&2; exit 1; }
# Hand the edits back to the series: the next apply-patches.sh run reapplies them.
git -C "$checkout" apply --reverse "$out"
unset GIT_INDEX_FILE
rm -f "$state/applied.list.tmp"
echo "Wrote $out and reverted the edits in $checkout; the next build applies the patch."
