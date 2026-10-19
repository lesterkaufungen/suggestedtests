"""Registers the split repos with their package indexes, for tool/release_publish.sh.

    python3 tool/release_registries.py packagist <split repo URL> <version>
    python3 tool/release_registries.py spi <split repo URL>
    python3 tool/release_registries.py check            # preflight: the logins are usable

packagist: creates the package on packagist.org the first time (needs the main
API token), afterwards asks Packagist to re-crawl the repo, then waits until
<version> is listed. The login is packagist.token at the repo root,
"USERNAME:TOKEN" (gitignored, like the other tokens).

spi: the Swift Package Index lists packages from packages.json in
SwiftPackageIndex/PackageList and polls their tags itself, so a package needs
adding once. If the URL isn't listed and no pull request for it is open, this
forks PackageList with github.token, adds the URL exactly as the index's own
bot does (normalized, sorted by lowercased URL, Swift's pretty-printed JSON)
and opens the pull request; the index's CI validates it there.

Tokens are read from the files and sent only in HTTP headers.
"""

from __future__ import annotations

import base64
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPI_REPO = "SwiftPackageIndex/PackageList"
BRANCH = "add-suggestedtests-swift"


def _token(name: str) -> str:
    path = ROOT / f"{name}.token"
    if not path.is_file():
        sys.exit(f"no {path.name} at the repo root")
    return path.read_text().strip()


def _request(
    method: str, url: str, headers: dict[str, str], body: object | None = None
) -> tuple[int, object]:
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "User-Agent": "suggestedtests-release",
            **headers,
            **({"Content-Type": "application/json"} if data is not None else {}),
        },
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                text = response.read().decode()
                return response.status, (json.loads(text) if text.strip() else None)
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors="replace")
            try:
                return e.code, json.loads(text)
            except ValueError:
                return e.code, text
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == 3:
                raise
            time.sleep(5 * (attempt + 1))
    raise AssertionError("unreachable")


# ------------------------------------------------------------------ packagist --


def _packagist_headers() -> dict[str, str]:
    login = _token("packagist")
    if ":" not in login:
        sys.exit("packagist.token must be USERNAME:TOKEN (the main API token from packagist.org/profile)")
    return {"Authorization": f"Bearer {login}"}


def _composer_name() -> str:
    return json.loads((ROOT / "packages/php/composer.json").read_text())["name"]


def packagist(repo_url: str, version: str) -> None:
    name = _composer_name()
    status, _ = _request("GET", f"https://packagist.org/packages/{name}.json", {})
    endpoint = "update-package" if status == 200 else "create-package"
    status, answer = _request(
        "POST", f"https://packagist.org/api/{endpoint}", _packagist_headers(), {"repository": repo_url}
    )
    if status >= 300 or not isinstance(answer, dict) or answer.get("status") != "success":
        sys.exit(f"packagist {endpoint} failed ({status}): {answer}")
    print(
        f"packagist: {'created' if endpoint == 'create-package' else 'updated'} {name}, waiting for {version}"
    )
    # Composer v2 metadata; Packagist crawls within a minute or two.
    wanted = {version, f"v{version}"}
    for _ in range(60):
        status, meta = _request("GET", f"https://repo.packagist.org/p2/{name}.json?t={time.time():.0f}", {})
        if status == 200 and isinstance(meta, dict):
            versions = {v.get("version") for v in meta.get("packages", {}).get(name, [])}
            if versions & wanted:
                print(f"packagist: {name} {version} is live: https://packagist.org/packages/{name}")
                return
        time.sleep(10)
    sys.exit(
        f"packagist: {version} didn't appear within 10 minutes; check https://packagist.org/packages/{name}"
    )


# ------------------------------------------------------------------------ spi --


def _github_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {_token('github')}", "Accept": "application/vnd.github+json"}


def _normalized(url: str) -> str:
    url = url.replace("http://", "https://", 1)
    return url if url.endswith(".git") else url + ".git"


def _with_package(text: str, url: str) -> str:
    """packages.json with `url` added, formatted like the index's add_package.swift."""
    packages = json.loads(text)
    packages.append(url)
    packages.sort(key=str.lower)
    # Swift's JSONEncoder [.prettyPrinted, .withoutEscapingSlashes]: two spaces, no final newline.
    return "[\n" + ",\n".join(f"  {json.dumps(p)}" for p in packages) + "\n]"


def spi(repo_url: str) -> None:
    url = _normalized(repo_url)
    headers = _github_headers()
    api = "https://api.github.com"
    status, listing = _request("GET", f"{api}/repos/{SPI_REPO}/contents/packages.json", headers)
    if status != 200:
        sys.exit(f"spi: can't read {SPI_REPO}/packages.json ({status})")
    upstream = base64.b64decode(listing["content"]).decode()
    if url.lower() in (p.lower() for p in json.loads(upstream)):
        print(f"spi: {url} is listed: https://swiftpackageindex.com/{url[len('https://github.com/') : -4]}")
        return
    status, me = _request("GET", f"{api}/user", headers)
    user = me["login"]
    status, pulls = _request("GET", f"{api}/repos/{SPI_REPO}/pulls?state=open&head={user}:{BRANCH}", headers)
    if status == 200 and pulls:
        print(f"spi: pull request already open: {pulls[0]['html_url']}")
        return

    # A fork, up to date with upstream, with a branch from upstream's main.
    status, fork = _request("POST", f"{api}/repos/{SPI_REPO}/forks", headers, {"default_branch_only": True})
    if status not in (200, 202):
        sys.exit(f"spi: can't fork {SPI_REPO} ({status}): {fork}")
    fork_name = fork["full_name"]
    for _ in range(30):
        if _request("GET", f"{api}/repos/{fork_name}", headers)[0] == 200:
            break
        time.sleep(5)
    _request("POST", f"{api}/repos/{fork_name}/merge-upstream", headers, {"branch": "main"})
    status, main = _request("GET", f"{api}/repos/{SPI_REPO}/git/ref/heads/main", headers)
    sha = main["object"]["sha"]
    status, ref = _request("GET", f"{api}/repos/{fork_name}/git/ref/heads/{BRANCH}", headers)
    if status == 200:
        _request(
            "PATCH", f"{api}/repos/{fork_name}/git/refs/heads/{BRANCH}", headers, {"sha": sha, "force": True}
        )
    else:
        status, ref = _request(
            "POST", f"{api}/repos/{fork_name}/git/refs", headers, {"ref": f"refs/heads/{BRANCH}", "sha": sha}
        )
        if status != 201:
            sys.exit(f"spi: can't create the branch ({status}): {ref}")

    status, current = _request("GET", f"{api}/repos/{fork_name}/contents/packages.json?ref={BRANCH}", headers)
    text = base64.b64decode(current["content"]).decode()
    status, commit = _request(
        "PUT",
        f"{api}/repos/{fork_name}/contents/packages.json",
        headers,
        {
            "message": f"Add {url}",
            "content": base64.b64encode(_with_package(text, url).encode()).decode(),
            "sha": current["sha"],
            "branch": BRANCH,
        },
    )
    if status not in (200, 201):
        sys.exit(f"spi: can't commit packages.json ({status}): {commit}")
    status, pull = _request(
        "POST",
        f"{api}/repos/{SPI_REPO}/pulls",
        headers,
        {
            "title": f"Add {url[len('https://github.com/') : -4]}",
            "head": f"{user}:{BRANCH}",
            "base": "main",
            "body": f"Adds {url}: test helpers (performance and memory budgets, polling, seeded data) "
            "for XCTest and Swift Testing, Swift 5.10+, macOS / Linux / Windows.",
        },
    )
    if status != 201:
        sys.exit(f"spi: can't open the pull request ({status}): {pull}")
    print(f"spi: opened {pull['html_url']}")


# ---------------------------------------------------------------------- check --


def check(packages: list[str]) -> None:
    problems = []
    if "php" in packages:
        path = ROOT / "packagist.token"
        if not path.is_file() or ":" not in path.read_text():
            problems.append(
                "php: no packagist.token (USERNAME:TOKEN, the main API token from packagist.org/profile)"
            )
    if "swift" in packages:
        status, _ = _request("GET", "https://api.github.com/user", _github_headers())
        if status != 200:
            problems.append(f"swift: github.token can't reach the GitHub API ({status})")
    for problem in problems:
        print(problem)
    sys.exit(1 if problems else 0)


def main() -> None:
    args = sys.argv[1:]
    if args[:1] == ["packagist"] and len(args) == 3:
        packagist(args[1], args[2])
    elif args[:1] == ["spi"] and len(args) == 2:
        spi(args[1])
    elif args[:1] == ["check"]:
        check(args[1:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
