#!/usr/bin/env bash
# Publishes released packages without compiling Rust: the prebuilts are the
# ones tool/release_build.sh built and checksummed (CLAUDE.md, Releasing).
# Only run it when the maintainer asks for a release to be published.
#
#   tool/release_publish.sh --dry-run all    # every check, nothing uploaded or pushed
#   tool/release_publish.sh --push-only all  # every check, then push main (no tags) for tool/macos_check.sh
#   tool/release_publish.sh all              # every package with a release tag on HEAD
#   tool/release_publish.sh python js        # just these
#
# Checks first, then: push main + tags to GitHub (the Go module is its tag),
# verify GitHub serves the built prebuilts, then pub.dev, PyPI, npm, Maven
# Central (jar + AAR), the split repos, Packagist and the Swift Package Index
# (a pull request the first time). Versions
# already on a registry are skipped, so a failed run can simply be repeated.
set -euo pipefail
# shellcheck source=tool/release_common.sh
source "$(dirname "$0")/release_common.sh"

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

dry_run=0 push_only=0
case "${1:-}" in
  --dry-run) dry_run=1 && shift ;;
  # Tags aren't pushed: the Go module's tag would publish it.
  --push-only) push_only=1 && shift ;;
esac
(($#)) || usage

hide_rust
# Fail instead of asking for a password: in the terminal, or in a dialog
# (editors such as VS Code set GIT_ASKPASS). Logins are the tokens in the
# gitignored <name>.token files at the root, else the usual ones: git's
# credential helper, UV_PUBLISH_TOKEN, npm login, ~/.m2/settings.xml.
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false GCM_INTERACTIVE=never
token_of() { tr -d '[:space:]' <"$root/$1.token"; }
github_token="$root/github.token"
if [[ -f "$root/pypi.token" ]]; then
  UV_PUBLISH_TOKEN="$(token_of pypi)"
  export UV_PUBLISH_TOKEN
fi
if [[ -f "$root/npm.token" ]]; then
  # npm expands ${NPM_TOKEN} itself, so the token isn't written to a file.
  NPM_TOKEN="$(token_of npm)"
  NPM_CONFIG_USERCONFIG="$release/npmrc"
  export NPM_TOKEN NPM_CONFIG_USERCONFIG
  mkdir -p "$release"
  { cat "$HOME/.npmrc" 2>/dev/null || true
    echo "//registry.npmjs.org/:_authToken=\${NPM_TOKEN}"; } >"$NPM_CONFIG_USERCONFIG"
fi
maven_settings=()
if [[ -f "$root/maven.token" ]]; then
  # The <server> snippet Central Portal generates for a user token. Maven
  # reads it as ${env.*} from a generated settings.xml, like npm above.
  { IFS= read -r MAVEN_CENTRAL_USERNAME && IFS= read -r MAVEN_CENTRAL_PASSWORD; } < <(python3 -I -c '
import sys, xml.etree.ElementTree as ET
server = ET.parse(sys.argv[1]).getroot()
print(server.findtext("username").strip())
print(server.findtext("password").strip())' "$root/maven.token")
  export MAVEN_CENTRAL_USERNAME MAVEN_CENTRAL_PASSWORD
  mkdir -p "$release"
  cat >"$release/settings.xml" <<'EOF'
<settings>
  <servers>
    <server>
      <id>central</id>
      <username>${env.MAVEN_CENTRAL_USERNAME}</username>
      <password>${env.MAVEN_CENTRAL_PASSWORD}</password>
    </server>
  </servers>
</settings>
EOF
  maven_settings=(-s "$release/settings.xml")
fi
# Central Portal API: the Bearer token is base64(username:password).
central_auth() {
  if [[ -n "${MAVEN_CENTRAL_USERNAME:-}" ]]; then
    printf 'Authorization: Bearer %s\n' "$(printf '%s:%s' "$MAVEN_CENTRAL_USERNAME" "$MAVEN_CENTRAL_PASSWORD" | base64 -w0)"
    return
  fi
  python3 - <<'EOF'
import base64, os, xml.etree.ElementTree as ET
ns = {"m": "http://maven.apache.org/SETTINGS/1.0.0"}
root = ET.parse(os.path.expanduser("~/.m2/settings.xml")).getroot()
find = lambda e, tag: e.find(f"m:{tag}", ns) if e.find(f"m:{tag}", ns) is not None else e.find(tag)
servers = find(root, "servers")
for s in servers if servers is not None else []:
    if find(s, "id").text == "central":
        user, password = find(s, "username").text, find(s, "password").text
        print("Authorization: Bearer " + base64.b64encode(f"{user}:{password}".encode()).decode())
EOF
}
# curl reads the header from a pipe, so the token isn't in its arguments.
central_api() { curl_ -H @<(central_auth) "$@"; }
if [[ -f "$github_token" ]]; then
  # git runs the helper with "get"; the token goes from the file to git's
  # stdin, never into a command line or the log.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.https://github.com.helper
  export GIT_CONFIG_VALUE_0="!f() { if [ \"\$1\" = get ]; then printf 'username=x-access-token\\npassword=%s\\n' \"\$(tr -d '[:space:]' < '$github_token')\"; fi; }; f"
fi
export PATH="$HOME/development/flutter/bin:$HOME/.local/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/share/jdk21}"
repo=lesterkaufungen/suggestedtests
php_repo="https://github.com/lesterkaufungen/suggestedtests-php.git"
php_split="${SUGGESTEDTESTS_PHP_SPLIT:-$release/php-split}"
swift_repo="https://github.com/lesterkaufungen/suggestedtests-swift.git"
swift_split="${SUGGESTEDTESTS_SWIFT_SPLIT:-$release/swift-split}"
group=io/github/lesterkaufungen
curl_() { curl -fsSL --retry 3 --retry-all-errors --max-time 120 "$@"; }

head="$(git -C "$root" rev-parse HEAD)"
tagged_on_head() { [[ "$(git -C "$root" rev-parse -q --verify "refs/tags/$(tag_of "$1")^{commit}" 2>/dev/null)" == "$head" ]]; }

if [[ "$1" == all ]]; then
  selected=()
  for p in "${packages[@]}"; do
    if tagged_on_head "$p"; then selected+=("$p"); fi
  done
  ((${#selected[@]})) || { echo "no package has a release tag on HEAD" >&2 && exit 1; }
else
  selected=("$@")
  for p in "${selected[@]}"; do
    [[ " ${packages[*]} " == *" $p "* ]] || usage
  done
fi

# ------------------------------------------------------------- preflight --
problems=()
problem() { problems+=("$*"); }

step "checks for: ${selected[*]}"
[[ "$(git -C "$root" branch --show-current)" == main ]] || problem "not on main"
[[ -z "$(git -C "$root" status --porcelain)" ]] || problem "uncommitted changes (git status)"

if [[ ! -f "$manifest" ]]; then
  problem "no ${manifest#"$root"/}: run tool/release_build.sh"
else
  (cd "$root" && sha256sum --quiet -c "$manifest") || problem "prebuilts changed since tool/release_build.sh"
  diff <(cut -d' ' -f3- "$manifest" | sed 's/^\*//') <(prebuilt_files) >/dev/null ||
    problem "prebuilt files added or removed since tool/release_build.sh"
fi
for f in "$root"/packages/go/internal/native/prebuilt/*/*; do
  cmp -s "$f" "$root/native/prebuilt/${f#"$root"/packages/go/internal/native/prebuilt/}" ||
    problem "packages/go copy differs from native/prebuilt: ${f#"$root"/} (tool/stage.sh go)"
done

for p in "${selected[@]}"; do
  v="$(version_of "$p")"
  [[ -n "$v" ]] || { problem "$p: no version" && continue; }
  grep -q "^## $v\b" "$root/packages/$p/CHANGELOG.md" || problem "$p: CHANGELOG.md has no '## $v'"
  tagged_on_head "$p" || problem "$p: tag $(tag_of "$p") doesn't point at HEAD"
done
if [[ " ${selected[*]} " == *" java "* ]]; then
  aar_version="$(sed -n 's|^  <version>\(.*\)</version>|\1|p' "$root/packages/java/android/pom.xml" | head -1)"
  [[ "$aar_version" == "$(version_of java)" ]] ||
    problem "java: android/pom.xml is $aar_version, pom.xml is $(version_of java)"
fi

# What's already out, and the logins for what isn't.
declare -A done_
remote_tag() { git -C "$root" ls-remote --exit-code --tags "$1" "refs/tags/$2" >/dev/null 2>&1; }
for p in "${selected[@]}"; do
  v="$(version_of "$p")"
  case "$p" in
    dart) curl_ -o /dev/null "https://pub.dev/api/packages/suggestedtests/versions/$v" 2>/dev/null && done_[$p]=1 ;;
    python) curl_ -o /dev/null "https://pypi.org/pypi/suggestedtests/$v/json" 2>/dev/null && done_[$p]=1 ;;
    js) [[ "$(npm view "suggestedtests@$v" version 2>/dev/null)" == "$v" ]] && done_[$p]=1 ;;
    java)
      curl_ -o /dev/null "https://repo1.maven.org/maven2/$group/suggestedtests/$v/suggestedtests-$v.pom" 2>/dev/null && done_[java]=1
      curl_ -o /dev/null "https://repo1.maven.org/maven2/$group/suggestedtests-android/$v/suggestedtests-android-$v.pom" 2>/dev/null && done_[aar]=1
      ;;
    php) remote_tag "$php_repo" "v$v" && done_[$p]=1 ;;
    swift) remote_tag "$swift_repo" "$v" && done_[$p]=1 ;;
    go) remote_tag origin "$(tag_of go)" && done_[$p]=1 ;;
  esac
  if [[ -n "${done_[$p]:-}" ]]; then echo "$p $v: already published, skipped"; fi
done

git -C "$root" push --dry-run origin main >/dev/null 2>&1 || problem "github: can't push to origin (credentials?)"
for p in "${selected[@]}"; do
  [[ -n "${done_[$p]:-}" ]] && [[ "$p" != java || -n "${done_[aar]:-}" ]] && continue
  case "$p" in
    dart)
      [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/dart/pub-credentials.json" ]] || problem "dart: not logged in (flutter pub login)"
      inotify_check >/dev/null 2>&1 || problem "dart: no inotify watches left, so pub's analyzer would hang (see tool/release_common.sh inotify_check)"
      ;;
    python) [[ -n "${UV_PUBLISH_TOKEN:-}" ]] || problem "python: no pypi.token or UV_PUBLISH_TOKEN (a PyPI API token)" ;;
    js) npm whoami >/dev/null 2>&1 || problem "js: npm whoami fails (npm.token or npm login)" ;;
    java)
      if [[ -z "${MAVEN_CENTRAL_USERNAME:-}" ]] && ! grep -q '<id>central</id>' "$HOME/.m2/settings.xml" 2>/dev/null; then
        problem "java: no maven.token or 'central' server in ~/.m2/settings.xml (Central Portal token)"
      else
        central_api -o /dev/null "https://central.sonatype.com/api/v1/publisher/published?namespace=io.github.lesterkaufungen&name=suggestedtests&version=$(version_of java)" 2>/dev/null ||
          problem "java: Central Portal rejects the token"
      fi
      [[ -n "$(gpg --list-secret-keys 2>/dev/null)" ]] || problem "java: no GPG secret key to sign with"
      ;;
    swift) git ls-remote "$swift_repo" >/dev/null 2>&1 || problem "swift: can't reach $swift_repo" ;;
    php) git ls-remote "$php_repo" >/dev/null 2>&1 || problem "php: can't reach $php_repo"
      ;;
  esac
done

registries=()
for p in "${selected[@]}"; do [[ "$p" == php || "$p" == swift ]] && registries+=("$p"); done
if ((${#registries[@]})); then
  while read -r line; do problem "$line"; done < <(python3 "$root/tool/release_registries.py" check "${registries[@]}" || true)
fi

# ------------------------------------------------- artifacts (no Rust) --
work="$release/publish"
rm -rf "$work" && mkdir -p "$work"
trap '"$root/tool/stage.sh" dart --clean >/dev/null 2>&1 || true; "$root/tool/stage.sh" swift --clean >/dev/null 2>&1 || true' EXIT
artifacts=()
for p in "${selected[@]}"; do
  v="$(version_of "$p")"
  case "$p" in
    python)
      step "python: build $v"
      (cd "$root/packages/python" && uv build -q --out-dir "$work/python")
      artifacts+=("$work/python/suggestedtests-$v-py3-none-any.whl:19")
      ;;
    js)
      step "js: pack $v"
      (cd "$root/packages/js" && npm pack -q --pack-destination "$work" >/dev/null)
      artifacts+=("$work/suggestedtests-$v.tgz:15")
      ;;
    java)
      step "java: package $v and the AAR"
      (cd "$root/packages/java" && ./mvnw -B -q clean package -DskipTests && "$root/tool/build_aar.sh")
      artifacts+=("$root/packages/java/target/suggestedtests-$v.jar:15" "$root/packages/java/target/suggestedtests-android-$v.aar:4")
      ;;
    php)
      "$root/tool/stage.sh" php >/dev/null
      artifacts+=("$root/packages/php/native/prebuilt:19")
      ;;
    swift)
      "$root/tool/stage.sh" swift >/dev/null
      artifacts+=("$root/packages/swift/Sources/SuggestedTests/Prebuilt:15")
      ;;
    dart)
      "$root/tool/stage.sh" dart >/dev/null
      artifacts+=("$root/packages/dart/native/prebuilt:19")
      ;;
  esac
done
artifacts+=("$root/packages/go/internal/native/prebuilt:19")
if [[ -f "$manifest" ]]; then
  step "the native libraries in every artifact are the built ones"
  python3 "$root/tool/release_verify.py" "$manifest" "${artifacts[@]}" || problem "artifacts don't contain the built prebuilts"
fi

if ((${#problems[@]})); then
  printf '\n!! %s\n' "${problems[@]}" >&2
  exit 1
fi
if ((dry_run)); then
  step "dry run: everything checks out; nothing was uploaded or pushed"
  exit 0
fi

# ---------------------------------------------------------------- publish --
# Commits packages/<name> (with its staged prebuilts) to a split repo, tags it
# and pushes. The package's .gitignore keeps the staged copy out of the
# monorepo; in the split repo it must be committed, so that line is dropped.
split_release() { # <repo> <dir> <package dir> <tag> <ignore line> <prebuilt dir> <count> [rsync args]
  local split_repo="$1" dir="$2" package="$3" tag="$4" ignored="$5" prebuilt="$6" count="$7"
  shift 7
  [[ -d "$dir/.git" ]] || git clone -q "$split_repo" "$dir"
  # A new, empty split repo: its first push creates main, not master.
  git -C "$dir" rev-parse -q --verify HEAD >/dev/null || git -C "$dir" symbolic-ref HEAD refs/heads/main
  # Commit as the monorepo does (its identity may be in its .git/config only).
  git -C "$dir" config user.name "$(git -C "$root" config user.name)"
  git -C "$dir" config user.email "$(git -C "$root" config user.email)"
  git -C "$dir" pull -q --ff-only || true
  rsync -a --delete --exclude .git "$@" "$root/$package/" "$dir/"
  grep -vxF "$ignored" "$dir/.gitignore" >"$dir/.gitignore.split" || true
  mv "$dir/.gitignore.split" "$dir/.gitignore"
  python3 "$root/tool/release_verify.py" "$manifest" "$dir/$prebuilt:$count"
  git -C "$dir" add -A
  local tracked
  tracked="$(git -C "$dir" ls-files "$prebuilt" | grep -c 'suggestedtests_native' || true)"
  [[ "$tracked" == "$count" ]] || { echo "!! $split_repo would get $tracked of $count prebuilts" >&2 && exit 1; }
  git -C "$dir" commit -q -m "Release $tag" -m "From $repo@$head ($package)."
  git -C "$dir" tag "$tag"
  git -C "$dir" push -q origin HEAD "refs/tags/$tag"
}

step "github: push main and tags"
tags=()
if ((!push_only)); then
  for p in "${selected[@]}"; do tags+=("refs/tags/$(tag_of "$p")"); done
fi
git -C "$root" push origin main "${tags[@]}"

step "github serves the built prebuilts at $head"
# Go fetches the module from git, and native/prebuilt is the canonical copy.
while read -r digest path; do
  path="${path#\*}"
  got="$(curl_ "https://raw.githubusercontent.com/$repo/$head/$path" | sha256sum | cut -d' ' -f1)"
  [[ "$got" == "$digest" ]] || { echo "!! GitHub serves a different $path" >&2 && exit 1; }
done <"$manifest"
echo "all $(wc -l <"$manifest") files match"
if ((push_only)); then
  step "pushed main (no tags, nothing uploaded): run tool/macos_check.sh, then publish without --push-only"
  exit 0
fi

for p in "${selected[@]}"; do
  v="$(version_of "$p")"
  case "$p" in
    dart)
      [[ -n "${done_[dart]:-}" ]] && continue
      step "dart: pub.dev $v"
      (cd "$root/packages/dart" && flutter pub publish --force)
      ;;
    python)
      [[ -n "${done_[python]:-}" ]] && continue
      step "python: PyPI $v"
      uv publish "$work/python/suggestedtests-$v"*
      ;;
    js)
      [[ -n "${done_[js]:-}" ]] && continue
      step "js: npm $v"
      npm publish "$work/suggestedtests-$v.tgz" --access public
      ;;
    java)
      cd "$root/packages/java"
      if [[ -z "${done_[java]:-}" ]]; then
        step "java: Maven Central $v (jar)"
        ./mvnw -B "${maven_settings[@]}" -P release deploy -DskipTests
      fi
      if [[ -z "${done_[aar]:-}" ]]; then
        step "java: Maven Central $v (AAR)"
        [[ -f "target/suggestedtests-$v-sources.jar" ]] || ./mvnw -B -q -P release package -DskipTests
        "$root/tool/build_aar.sh"
        python3 "$root/tool/release_verify.py" "$manifest" "target/suggestedtests-android-$v.aar:4"
        # Central Portal's upload API: a signed, checksummed bundle.
        bundle="$work/aar/$group/suggestedtests-android/$v"
        rm -rf "$work/aar" && mkdir -p "$bundle"
        cp "target/suggestedtests-android-$v.aar" "$bundle/"
        cp android/pom.xml "$bundle/suggestedtests-android-$v.pom"
        cp "target/suggestedtests-$v-sources.jar" "$bundle/suggestedtests-android-$v-sources.jar"
        cp "target/suggestedtests-$v-javadoc.jar" "$bundle/suggestedtests-android-$v-javadoc.jar"
        for f in "$bundle"/*; do
          gpg --batch --yes --armor --detach-sign "$f"
          md5sum "$f" | cut -d' ' -f1 >"$f.md5"
          sha1sum "$f" | cut -d' ' -f1 >"$f.sha1"
        done
        (cd "$work/aar" && zip -q -r bundle.zip io)
        id="$(central_api -X POST -F "bundle=@$work/aar/bundle.zip" \
          "https://central.sonatype.com/api/v1/publisher/upload?name=suggestedtests-android-$v&publishingType=AUTOMATIC")"
        echo "deployment $id"
        for _ in $(seq 120); do
          state="$(central_api -X POST \
            "https://central.sonatype.com/api/v1/publisher/status?id=$id" | python3 -c 'import json,sys; print(json.load(sys.stdin)["deploymentState"])')"
          echo "  $state"
          case "$state" in
            PUBLISHING | PUBLISHED) break ;;
            FAILED) central_api -X POST "https://central.sonatype.com/api/v1/publisher/status?id=$id" >&2; exit 1 ;;
          esac
          sleep 10
        done
      fi
      cd "$root"
      ;;
    php)
      if [[ -z "${done_[php]:-}" ]]; then
        step "php: split repo v$v"
        split_release "$php_repo" "$php_split" packages/php "v$v" /native/ native/prebuilt 19 \
          --exclude vendor/ --exclude vendor-7.4/ --exclude 'composer-7.4.*' --exclude composer.lock \
          --exclude .phpunit.result.cache
      fi
      # Also when the split repo had the tag: a failed earlier run may not have got this far.
      step "php: Packagist"
      python3 "$root/tool/release_registries.py" packagist "$php_repo" "$v"
      ;;
    swift)
      if [[ -z "${done_[swift]:-}" ]]; then
        step "swift: split repo $v (SwiftPM reads it)"
        split_release "$swift_repo" "$swift_split" packages/swift "$v" /Sources/SuggestedTests/Prebuilt/ \
          Sources/SuggestedTests/Prebuilt 15 --exclude .build/ --exclude .swiftpm/ --exclude Package.resolved
      fi
      step "swift: Swift Package Index"
      python3 "$root/tool/release_registries.py" spi "$swift_repo"
      ;;
    go) echo "go: published by its tag ($(tag_of go))" ;;
  esac
done

step "published: ${selected[*]}"
