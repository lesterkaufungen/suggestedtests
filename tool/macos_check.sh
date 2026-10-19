#!/usr/bin/env bash
# Runs the macOS check (.github/workflows/macos.yml) on GitHub's Apple Silicon
# and Intel runners for the pushed main, waits for it and prints each job's
# result. Run it after `tool/release_publish.sh --push-only`, before the real
# publish: this machine can't run macOS.
#
#   tool/macos_check.sh
#
# Uses the token in github.token (it needs the "actions" scope, or "workflow"
# for a classic token), which goes to curl through a pipe, never a command line.
set -euo pipefail
# shellcheck source=tool/release_common.sh
source "$(dirname "$0")/release_common.sh"

repo=lesterkaufungen/suggestedtests
api="https://api.github.com/repos/$repo/actions"
token_file="$root/github.token"
[[ -f "$token_file" ]] || { echo "no github.token at the repo root" >&2 && exit 1; }
auth() { printf 'Authorization: Bearer %s\nAccept: application/vnd.github+json\n' "$(tr -d '[:space:]' <"$token_file")"; }
gh_api() { curl -fsSL --retry 3 --retry-all-errors --max-time 60 -H @<(auth) "$@"; }
json() { python3 -c "import json, sys; d = json.load(sys.stdin); print($1)"; }

head="$(git -C "$root" rev-parse HEAD)"
remote="$(git -C "$root" ls-remote origin refs/heads/main | cut -f1)"
[[ "$remote" == "$head" ]] ||
  { echo "GitHub's main is ${remote:-missing}, not HEAD $head: run tool/release_publish.sh --push-only first" >&2 && exit 1; }

step "macos-check: starting it for $head"
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh_api -X POST "$api/workflows/macos.yml/dispatches" -d '{"ref":"main"}'

id=""
for _ in $(seq 30); do
  sleep 5
  id="$(gh_api "$api/workflows/macos.yml/runs?event=workflow_dispatch&branch=main&per_page=5" |
    json "next((str(r['id']) for r in d['workflow_runs'] if r['head_sha'] == '$head' and r['created_at'] >= '$started'), '')")"
  [[ -n "$id" ]] && break
done
[[ -n "$id" ]] || { echo "the run didn't appear on GitHub" >&2 && exit 1; }
echo "https://github.com/$repo/actions/runs/$id"

status=""
while [[ "$status" != completed ]]; do
  sleep 30
  status="$(gh_api "$api/runs/$id" | json "d['status']")"
  echo "  $status"
done

step "macos-check: results"
gh_api "$api/runs/$id/jobs?per_page=100" |
  json "'\n'.join(f\"{j['conclusion'] or j['status']:>9}  {j['name']}\" for j in sorted(d['jobs'], key=lambda j: j['name']))"
conclusion="$(gh_api "$api/runs/$id" | json "d['conclusion']")"
[[ "$conclusion" == success ]] || { echo "!! macos-check: $conclusion" >&2 && exit 1; }
echo "macos-check passed: publish with tool/release_publish.sh <packages|all>"
