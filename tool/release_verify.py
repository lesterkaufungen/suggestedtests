#!/usr/bin/env python3
"""Checks that the native libraries inside release artifacts are the ones
tool/release_build.sh built, byte for byte (SHA-256 against its manifest).

    tool/release_verify.py release/prebuilt.sha256 dist/x.whl:19 x.tgz:15 x.jar:15 x.aar:4 dir/:15

Each argument is an artifact (wheel/jar/aar: zip, npm: .tgz, or a directory)
and how many native libraries it must contain. A library is matched to
native/prebuilt/<platform>/<file> by its last two path components; an AAR's
jni/<abi>/ is android-<abi>/.
"""

from __future__ import annotations

import hashlib
import sys
import tarfile
import zipfile
from pathlib import Path

NAMES = ("suggestedtests_native.", "libsuggestedtests_native.")


def native_entries(artifact: Path):
    """(path inside the artifact, bytes) of every native library in it."""
    if artifact.is_dir():
        for f in sorted(artifact.rglob("*")):
            if f.is_file() and f.name.startswith(NAMES):
                yield f.relative_to(artifact).as_posix(), f.read_bytes()
    elif artifact.suffix == ".tgz":
        with tarfile.open(artifact) as tar:
            for m in tar.getmembers():
                if m.isfile() and Path(m.name).name.startswith(NAMES):
                    yield m.name, tar.extractfile(m).read()
    else:
        with zipfile.ZipFile(artifact) as z:
            for name in z.namelist():
                if Path(name).name.startswith(NAMES):
                    yield name, z.read(name)


def prebuilt_path(entry: str) -> str:
    parts = entry.split("/")
    platform, file = parts[-2], parts[-1]
    if len(parts) >= 3 and parts[-3] == "jni":
        platform = f"android-{platform}"
    return f"native/prebuilt/{platform}/{file}"


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 64
    expected = {}
    for line in Path(argv[1]).read_text().splitlines():
        digest, path = line.split(maxsplit=1)
        expected[path.lstrip("*")] = digest

    problems = []
    for arg in argv[2:]:
        name, _, count = arg.rpartition(":")
        artifact = Path(name)
        found = 0
        for entry, data in native_entries(artifact):
            found += 1
            want = expected.get(prebuilt_path(entry))
            if want is None:
                problems.append(f"{artifact.name}: {entry} has no built counterpart")
            elif hashlib.sha256(data).hexdigest() != want:
                problems.append(f"{artifact.name}: {entry} is not the built {prebuilt_path(entry)}")
        if found != int(count):
            problems.append(f"{artifact.name}: {found} native libraries, expected {count}")
        print(f"{artifact.name}: {found} native libraries checked")
    for p in problems:
        print(f"!! {p}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
