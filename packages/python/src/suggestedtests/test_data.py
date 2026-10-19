"""Deterministic random test data."""

from __future__ import annotations

import random
import string as _string
import uuid as _uuid
from collections.abc import Callable, Iterable, Sequence
from datetime import datetime, timezone
from typing import TypeVar

T = TypeVar("T")

ALPHANUMERIC = _string.ascii_letters + _string.digits
"""The default alphabet of `TestData.string`."""

_WORDS = (
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india",
    "juliet", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo",
    "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu",
)  # fmt: skip


class TestData:
    """Seeded random test data.

    The same seed always produces the same values, so a failing test can be
    reproduced exactly. The `test_data` fixture picks a seed per test and
    prints it when the test fails::

        def test_signup(test_data):
            user = User(name=test_data.word(), email=test_data.email(),
                        age=test_data.integer(18, 90))
    """

    __test__ = False  # not a pytest test class

    def __init__(self, seed: int = 0) -> None:
        self.seed = seed
        """The seed this generator was created with."""
        self._random = random.Random(seed)

    @classmethod
    def random_seed(cls) -> TestData:
        """A generator with a random seed. Read `seed` to reproduce it."""
        return cls(random.SystemRandom().randrange(1 << 31))

    def integer(self, min: int = 0, max: int = 100) -> int:  # noqa: A002
        """An integer in `[min, max]` (inclusive)."""
        if max < min:
            raise ValueError(f"max ({max}) < min ({min})")
        return self._random.randint(min, max)

    def decimal(self, min: float = 0.0, max: float = 1.0) -> float:  # noqa: A002
        """A float in `[min, max)`."""
        if max < min:
            raise ValueError(f"max ({max}) < min ({min})")
        return min + self._random.random() * (max - min)

    def boolean(self, probability: float = 0.5) -> bool:
        """`True` with the given probability."""
        if not 0 <= probability <= 1:
            raise ValueError(f"probability must be in [0, 1], got {probability}")
        return self._random.random() < probability

    def string(self, length: int = 10, alphabet: str = ALPHANUMERIC) -> str:
        """A string of `length` characters drawn from `alphabet`."""
        if length < 0:
            raise ValueError(f"length must be >= 0, got {length}")
        if not alphabet:
            raise ValueError("alphabet must not be empty")
        return "".join(self._random.choice(alphabet) for _ in range(length))

    def word(self) -> str:
        """A short lowercase word."""
        return self.pick(_WORDS)

    def sentence(self, words: int = 6) -> str:
        """A sentence of `words` words, capitalised and ending with a period."""
        if words < 1:
            raise ValueError(f"words must be >= 1, got {words}")
        s = " ".join(self.word() for _ in range(words))
        return s[0].upper() + s[1:] + "."

    def email(self) -> str:
        """A syntactically valid address on the reserved `example.com` domain."""
        return f"{self.word()}.{self.string(5, _string.ascii_lowercase)}@example.com"

    def uuid(self) -> str:
        """A version 4 UUID string."""
        return str(_uuid.UUID(int=self._random.getrandbits(128), version=4))

    def date(self, start: datetime | None = None, end: datetime | None = None) -> datetime:
        """A UTC datetime in `[start, end]` (default 2000-01-01 to 2030-01-01)."""
        start = start or datetime(2000, 1, 1, tzinfo=timezone.utc)
        end = end or datetime(2030, 1, 1, tzinfo=timezone.utc)
        if end < start:
            raise ValueError("end is before start")
        return start + (end - start) * self._random.random()

    def pick(self, options: Sequence[T]) -> T:
        """A random element of `options`."""
        if not options:
            raise ValueError("options must not be empty")
        return self._random.choice(options)

    def list_of(self, count: int, generate: Callable[[TestData], T]) -> list[T]:
        """`count` values produced by `generate`."""
        if count < 0:
            raise ValueError(f"count must be >= 0, got {count}")
        return [generate(self) for _ in range(count)]

    def shuffled(self, items: Iterable[T]) -> list[T]:
        """A shuffled copy of `items`."""
        result = list(items)
        self._random.shuffle(result)
        return result

    def __repr__(self) -> str:
        return f"TestData(seed={self.seed})"
