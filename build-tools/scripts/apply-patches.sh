#!/bin/sh
# Applies an ordered patch series (<series-dir>/*.patch, sorted by name) to a git
# checkout and keeps the checkout in sync with the series on every run.
#
# usage: apply-patches.sh <checkout> <series-dir>
#
# State lives in <checkout>/.zig-patches:
#   applied.list  "<name> <sha256>" per applied patch, in order
#   store/<name>  copy of each applied patch, so a changed or removed patch can be
#                 reverted from exactly what was applied
#   index         private git index snapshotting the series-applied tree; the baseline
#                 new-patch.sh diffs against
# Only the first patch that differs from applied.list (and everything after it) is
# reverted and reapplied. An error leaves earlier patches applied and names the failing one.
set -eu

checkout=$(cd "$1" && pwd)
series=$(cd "$2" && pwd)
state=$checkout/.zig-patches
list=$state/applied.list
mkdir -p "$state/store"
touch "$list"

want=$(mktemp)
trap 'rm -f "$want"' EXIT
for patch in "$series"/*.patch; do
    [ -e "$patch" ] || continue
    printf '%s %s\n' "$(basename "$patch")" "$(shasum -a 256 "$patch" | cut -d' ' -f1)"
done >"$want"

keep=0
while :; do
    a=$(sed -n "$((keep + 1))p" "$list")
    b=$(sed -n "$((keep + 1))p" "$want")
    [ -n "$a" ] && [ "$a" = "$b" ] || break
    keep=$((keep + 1))
done

changed=0
i=$(wc -l <"$list" | tr -d ' ')
while [ "$i" -gt "$keep" ]; do
    name=$(sed -n "${i}p" "$list" | cut -d' ' -f1)
    if ! git -C "$checkout" apply --reverse "$state/store/$name"; then
        echo "Cannot revert previously applied patch $name in $checkout." >&2
        echo "Reset the checkout to pristine upstream and delete $state." >&2
        exit 1
    fi
    i=$((i - 1))
    head -n "$i" "$list" >"$list.tmp"
    mv "$list.tmp" "$list"
    changed=1
done

total=$(wc -l <"$want" | tr -d ' ')
i=$keep
while [ "$i" -lt "$total" ]; do
    i=$((i + 1))
    name=$(sed -n "${i}p" "$want" | cut -d' ' -f1)
    if ! git -C "$checkout" apply --check "$series/$name"; then
        echo "V8 patch does not apply: $series/$name" >&2
        echo "Rebase it against the selected upstream version (see build-tools/README.md)." >&2
        exit 1
    fi
    git -C "$checkout" apply "$series/$name"
    cp "$series/$name" "$state/store/$name"
    sed -n "${i}p" "$want" >>"$list"
    changed=1
done

# Refresh the baseline snapshot used by new-patch.sh.
if [ "$changed" = 1 ] || [ ! -f "$state/index" ]; then
    export GIT_INDEX_FILE=$state/index
    rm -f "$GIT_INDEX_FILE"
    git -C "$checkout" read-tree HEAD
    paths=$(for f in "$state"/store/*.patch; do
        [ -e "$f" ] && git -C "$checkout" apply --numstat "$f" | cut -f3
    done | sort -u)
    # shellcheck disable=SC2086
    [ -z "$paths" ] || (cd "$checkout" && git add -f -- $paths)
fi
