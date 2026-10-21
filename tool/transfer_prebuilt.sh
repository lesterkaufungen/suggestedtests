#!/usr/bin/env bash
# Copies the committed prebuilt binaries from another branch/tag/commit into
# this working tree, overwriting the local copies, WITHOUT checking out that
# ref (the rest of the working tree, including any uncommitted changes, is
# left alone):
#
#   tool/transfer_prebuilt.sh main        # pull main's prebuilts onto this branch's code
#   tool/transfer_prebuilt.sh local-only   # pull this branch's prebuilts onto main's code
#
# For checking, after a merge, that one branch's already-built native
# libraries still work against the other branch's binding/test code (ABI
# version, exports, loader behavior) -- run this, then the usual checks
# (cargo test --release --workspace, tool/check_load.py, each package's
# tests) against what landed. The transfer itself is left uncommitted so you
# can inspect `git status`/`git diff --stat` before deciding what to do with it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ref="${1:?usage: $0 <ref>}"
cd "$root"

for dir in native/prebuilt packages/go/internal/native/prebuilt; do
  git archive "$ref" -- "$dir" | tar -x -C "$root"
done

echo "Transferred $ref's prebuilt binaries into the working tree (uncommitted)."
