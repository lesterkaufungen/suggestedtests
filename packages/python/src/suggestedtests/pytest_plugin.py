"""pytest plugin, loaded automatically through the `pytest11` entry point.

Adds:

* the `test_data` fixture: a `TestData` with a fresh seed per test (or the
  one from `--st-seed`), printed in the report when the test fails;
* the `steps` fixture: a `Steps` for given/when/then blocks;
* the `requires_native_bridge` marker: skips the test, with the reason, where
  the native bridge can't be loaded.
"""

from __future__ import annotations

import random
from collections.abc import Generator
from typing import Any

import pytest

from .scenario import Steps
from .system_probe import SystemProbe
from .test_data import TestData

# An attribute rather than pytest.StashKey, which needs pytest 7.
_SEED_ATTR = "_suggestedtests_seed"


def pytest_addoption(parser: pytest.Parser) -> None:
    """Registers `--st-seed`."""
    group = parser.getgroup("suggestedtests")
    group.addoption(
        "--st-seed",
        type=int,
        default=None,
        metavar="SEED",
        help="seed for the test_data fixture (default: random per test)",
    )


def pytest_configure(config: pytest.Config) -> None:
    """Registers the `requires_native_bridge` marker."""
    config.addinivalue_line(
        "markers",
        "requires_native_bridge: skip unless the suggestedtests native bridge can be loaded",
    )


def pytest_runtest_setup(item: pytest.Item) -> None:
    """Skips tests marked `requires_native_bridge` where the bridge is missing."""
    if item.get_closest_marker("requires_native_bridge") and not SystemProbe.is_available():
        pytest.skip(SystemProbe.skip_reason() or "native bridge unavailable")


@pytest.fixture
def test_data(request: pytest.FixtureRequest) -> TestData:
    """Seeded `TestData`; the seed is reported if the test fails."""
    seed = request.config.getoption("--st-seed")
    if seed is None:
        seed = random.SystemRandom().randrange(1 << 31)
    setattr(request.node, _SEED_ATTR, seed)
    return TestData(seed)


@pytest.fixture
def steps() -> Steps:
    """A `Steps` for writing the test as given/when/then blocks."""
    return Steps()


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(
    item: pytest.Item, call: pytest.CallInfo[None]
) -> Generator[None, Any, None]:
    """Adds the `test_data` seed to the report of failed tests."""
    outcome = yield
    report = outcome.get_result()
    seed = getattr(item, _SEED_ATTR, None)
    if seed is not None and report.failed:
        report.sections.append(
            (
                "suggestedtests",
                f"test_data seed: {seed}\nreproduce with: pytest '{item.nodeid}' --st-seed={seed}",
            )
        )
