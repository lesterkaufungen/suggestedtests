"""Given/when/then steps as context managers."""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import AbstractContextManager, contextmanager


def add_note(error: BaseException, note: str) -> None:
    """`BaseException.add_note` on 3.11+; on older Pythons sets `__notes__`,
    which pytest (7.3+) and the exceptiongroup backport display too."""
    if hasattr(error, "add_note"):
        error.add_note(note)
    else:
        error.__notes__ = [*getattr(error, "__notes__", []), note]  # type: ignore[attr-defined]


class Steps:
    """Labels the parts of a test as given/when/then steps.

    Each step is a `with` block. When one fails, the original exception
    propagates unchanged (so pytest's assertion introspection still works)
    with a note naming the step and the steps that passed before it::

        def test_adding_items_updates_the_total(steps):
            with steps.given("an empty cart"):
                cart = Cart()
            with steps.when("two items are added"):
                cart.add(10)
                cart.add(20)
            with steps.then("the total is 30"):
                assert cart.total == 30

    The `steps` fixture provides one; construct `Steps()` directly elsewhere.
    """

    def __init__(self) -> None:
        self._passed: list[str] = []

    @property
    def passed(self) -> list[str]:
        """Steps that completed, as `Keyword: description` strings."""
        return list(self._passed)

    @contextmanager
    def _step(self, keyword: str, description: str) -> Iterator[None]:
        if not description:
            raise ValueError("step description must not be empty")
        label = f"{keyword}: {description}"
        try:
            yield
        except BaseException as error:
            note = f"Failed step: {label}"
            if self._passed:
                note += "\nPassed steps:" + "".join(f"\n  ✓ {s}" for s in self._passed)
            add_note(error, note)
            raise
        self._passed.append(label)

    def given(self, description: str) -> AbstractContextManager[None]:
        """Setup / preconditions."""
        return self._step("Given", description)

    def when(self, description: str) -> AbstractContextManager[None]:
        """The action under test."""
        return self._step("When", description)

    def then(self, description: str) -> AbstractContextManager[None]:
        """An expectation."""
        return self._step("Then", description)

    def and_(self, description: str) -> AbstractContextManager[None]:
        """Continues the previous step kind (e.g. a second `then`)."""
        return self._step("And", description)
