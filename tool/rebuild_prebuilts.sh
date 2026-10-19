#!/usr/bin/env bash
# Rebuilds every prebuilt native library after a native/ change and checks
# the result (tests/prebuilt.rs, among the rest of the workspace's tests).
# Run this and make sure it's clean before asking for a commit/push. Not the
# full release pipeline: that's tool/release_build.sh, which also runs every
# package's own checks and writes release/prebuilt.sha256 for a release.
#
#   tool/rebuild_prebuilts.sh
#
# CARGO_FEATURES enables extra cargo features in every prebuilt this run
# builds (passed straight to tool/build_prebuilt.sh). The `download` feature
# this used to test now lives only on the `local-only` branch (never
# pushed): run this from there, not from main, to use it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export CARGO_FEATURES="${CARGO_FEATURES:-}"

PATH="$HOME/.local/share/zig-0.14.1:$PATH" tool/build_prebuilt.sh linux
for os in macos windows android; do
  PATH="/opt/zig:$PATH" tool/build_prebuilt.sh "$os"
done

tool/stage.sh go

(cd native && cargo test --release --workspace ${CARGO_FEATURES:+--features "$CARGO_FEATURES"})

echo "tool/rebuild_prebuilts.sh: prebuilts rebuilt and checked OK"
