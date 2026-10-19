import re
from datetime import datetime, timezone

import pytest

from suggestedtests import TestData

UTC = timezone.utc


def test_same_seed_same_values():
    a, b = TestData(42), TestData(42)
    assert [a.integer() for _ in range(5)] == [b.integer() for _ in range(5)]
    assert a.email() == b.email() and a.uuid() == b.uuid()


def test_values_in_range():
    d = TestData(1)
    for _ in range(200):
        assert 3 <= d.integer(3, 5) <= 5
        assert 1.0 <= d.decimal(1.0, 2.0) < 2.0
    assert d.integer(7, 7) == 7


def test_strings():
    d = TestData(2)
    assert len(d.string(12)) == 12
    assert set(d.string(50, "ab")) <= {"a", "b"}
    assert re.fullmatch(r"[A-Z][a-z]+( [a-z]+){5}\.", d.sentence())
    assert re.fullmatch(r"[a-z]+\.[a-z]{5}@example\.com", d.email())
    uuid4 = r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
    assert re.fullmatch(uuid4, d.uuid())


def test_dates():
    d = TestData(3)
    start, end = datetime(2020, 1, 1, tzinfo=UTC), datetime(2020, 2, 1, tzinfo=UTC)
    assert start <= d.date(start, end) <= end


def test_collections():
    d = TestData(4)
    assert d.pick([1, 2, 3]) in (1, 2, 3)
    words = d.list_of(3, lambda g: g.word())
    assert len(words) == 3 and words == TestData(4).list_of(4, lambda g: g.word())[1:]
    assert sorted(d.shuffled(range(10))) == list(range(10))


@pytest.mark.parametrize(
    "call",
    [
        lambda d: d.integer(5, 1),
        lambda d: d.decimal(2, 1),
        lambda d: d.boolean(2),
        lambda d: d.string(-1),
        lambda d: d.string(3, ""),
        lambda d: d.sentence(0),
        lambda d: d.pick([]),
        lambda d: d.list_of(-1, str),
        lambda d: d.date(datetime(2021, 1, 1, tzinfo=UTC), datetime(2020, 1, 1, tzinfo=UTC)),
    ],
)
def test_validates_arguments(call):
    with pytest.raises(ValueError):
        call(TestData())


def test_random_seed_is_reproducible():
    d = TestData.random_seed()
    assert TestData(d.seed).integer() == d.integer()


def test_fixture_is_seeded(test_data):
    assert isinstance(test_data, TestData)


def test_not_collected_as_test_class():
    assert TestData.__test__ is False
