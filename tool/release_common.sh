# Sourced by tool/release_build.sh and tool/release_publish.sh.
# shellcheck shell=bash disable=SC2034 # the variables are used by the scripts that source this

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release="$root/release" # gitignored: logs, the prebuilt checksums, artifacts
manifest="$release/prebuilt.sha256"
mkdir -p "$release"

packages=(dart python js java php go swift)

# PATH without any directory holding cargo or rustc. Only tool/build_prebuilt.sh
# compiles Rust; everything else must use the prebuilts as they are, so a
# missing one fails instead of the Dart hook quietly building it.
no_rust_path() {
  local dir out=""
  local IFS=:
  for dir in $PATH; do
    [[ -x "$dir/cargo" || -x "$dir/rustc" || -x "$dir/rustup" ]] || out+="$dir:"
  done
  printf '%s' "${out%:}"
}

hide_rust() {
  PATH="$(no_rust_path)"
  export PATH
  unset CARGO RUSTC RUSTUP_TOOLCHAIN
  if command -v cargo >/dev/null || command -v rustc >/dev/null; then
    echo "cargo/rustc still on PATH" >&2
    exit 1
  fi
}

# The version a package releases: its manifest's, or (PHP, Go, Swift: none) the
# newest CHANGELOG entry's.
version_of() {
  case "$1" in
    dart) sed -n 's/^version: *//p' "$root/packages/dart/pubspec.yaml" ;;
    python) sed -n 's/^version = "\(.*\)"/\1/p' "$root/packages/python/pyproject.toml" ;;
    js) sed -n 's/^  "version": "\(.*\)",/\1/p' "$root/packages/js/package.json" ;;
    java) sed -n 's|^  <version>\(.*\)</version>|\1|p' "$root/packages/java/pom.xml" | head -1 ;;
    php | go | swift) sed -n 's/^## \([0-9][^ ]*\).*/\1/p' "$root/packages/$1/CHANGELOG.md" | head -1 ;;
    *) echo "unknown package: $1" >&2 && return 64 ;;
  esac
}

# The git tag of a package's release (CLAUDE.md, Releasing).
tag_of() {
  case "$1" in
    go) echo "packages/go/v$(version_of go)" ;;
    *) echo "$1-v$(version_of "$1")" ;;
  esac
}

# Every committed prebuilt: native/prebuilt/ and the Go module's copy.
prebuilt_files() {
  (cd "$root" && find native/prebuilt packages/go/internal/native/prebuilt -type f | LC_ALL=C sort)
}

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Fails if no inotify watch can be added: pub publish (also --dry-run) runs
# the Dart analyzer, which then retries for as long as the user's watches stay
# used up (Syncthing, IDEs), instead of failing.
inotify_check() {
  python3 -I - <<'EOF'
import ctypes, os, sys, tempfile
libc = ctypes.CDLL(None, use_errno=True)
fd = libc.inotify_init1(os.O_CLOEXEC)
if fd < 0:
    sys.exit(f"inotify: {os.strerror(ctypes.get_errno())} (fs.inotify.max_user_instances)")
d = tempfile.mkdtemp()
try:
    if libc.inotify_add_watch(fd, d.encode(), 0x2) < 0:  # IN_MODIFY
        limit = open("/proc/sys/fs/inotify/max_user_watches").read().strip()
        sys.exit(
            f"inotify: {os.strerror(ctypes.get_errno())}: all {limit} watches are used, so the Dart analyzer would hang.\n"
            "  Raise the limit: echo fs.inotify.max_user_watches=524288 | sudo tee /etc/sysctl.d/60-inotify.conf && sudo sysctl --system"
        )
finally:
    os.rmdir(d)
    os.close(fd)
EOF
}
