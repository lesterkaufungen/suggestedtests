"""Bundles the native bridge into the package.

From a monorepo checkout, copies every platform's C library from
`native/prebuilt/` to `suggestedtests/_prebuilt/`. Building a wheel from an
sdist reuses the copy the sdist already contains (force-included, because the
sdist's .gitignore lists it).
"""

from pathlib import Path

from hatchling.builders.hooks.plugin.interface import BuildHookInterface

LIBRARIES = (
    "libsuggestedtests_native.so",
    "libsuggestedtests_native.dylib",
    "suggestedtests_native.dll",
)


class CustomBuildHook(BuildHookInterface):
    def initialize(self, version, build_data):
        prebuilt = Path(self.root, "..", "..", "native", "prebuilt").resolve()
        if not prebuilt.is_dir():
            bundled = Path(self.root, "src", "suggestedtests", "_prebuilt")
            if bundled.is_dir() and self.target_name == "wheel":
                build_data["force_include"][str(bundled)] = "suggestedtests/_prebuilt"
            return
        for lib in sorted(prebuilt.glob("*/*")):
            if lib.name in LIBRARIES:
                target = f"suggestedtests/_prebuilt/{lib.parent.name}/{lib.name}"
                if self.target_name == "sdist":
                    target = f"src/{target}"
                build_data["force_include"][str(lib)] = target
