#!/bin/sh
# sync.sh [--check] ish-aok|qemu DIR -- bring a consumer's copies of these
# sources up to date with this repository, or with --check say whether they
# are (exit 1 and the file's name if one is not).
#
# Both consumers hold copies, not a submodule: they are public repositories,
# and this one may not be. The copies are never edited where they land. A
# change is made here, checked here (tools/check.sh), synced into iSH-AOK,
# whose tests are the ones that execute the gadgets, and then into the QEMU
# fork.
#
#   ish-aok DIR   an iSH-AOK checkout: riscv64/ is its jit/guest-riscv64,
#                 arm64/ its jit/guest-arm64, x87/ goes to jit/gadgets-aarch64
#   qemu DIR      a checkout of the QEMU fork (emkey1/qemu): its own
#                 scripts/aok-gadgets-sync.sh does it, because it also works
#                 out which gadgets each front end has
set -e
check=
[ "$1" = --check ] && { check=1; shift; }
kind=$1; dir=$2
here=$(cd "$(dirname "$0")/.." && pwd)
[ -n "$dir" ] && [ -d "$dir" ] || { echo "usage: $0 [--check] ish-aok|qemu DIR" >&2; exit 2; }
case $kind in
qemu)
    exec "$dir/scripts/aok-gadgets-sync.sh" ${check:+--check} "$here" ;;
ish-aok)
    rc=0
    each() {    # SUBDIR DEST
        for f in "$here/$1"/*; do
            [ -f "$f" ] || continue
            d=$dir/$2/$(basename "$f")
            if [ -n "$check" ]; then
                cmp -s "$f" "$d" || { echo "$2/$(basename "$f") differs from $1/$(basename "$f")" >&2; rc=1; }
            else
                cp "$f" "$d"
            fi
        done
    }
    each riscv64 jit/guest-riscv64
    each arm64 jit/guest-arm64
    each x87 jit/gadgets-aarch64
    [ -n "$check" ] && [ $rc = 0 ] && echo "iSH-AOK's copies match $(git -C "$here" rev-parse --short HEAD 2> /dev/null)"
    exit $rc ;;
*)  echo "usage: $0 [--check] ish-aok|qemu DIR" >&2; exit 2 ;;
esac
