import pytest

from suggestedtests import Steps


def test_fixture_runs_steps(steps):
    with steps.given("a list"):
        items = []
    with steps.when("an item is added"):
        items.append(1)
    with steps.then("it has one item"):
        assert items == [1]
    assert steps.passed == ["Given: a list", "When: an item is added", "Then: it has one item"]


def test_failure_keeps_exception_and_names_step():
    s = Steps()
    with s.given("setup"):
        pass
    with pytest.raises(AssertionError) as info:
        with s.then("the total is 30"):
            assert 20 == 30
    notes = info.value.__notes__
    assert notes == ["Failed step: Then: the total is 30\nPassed steps:\n  ✓ Given: setup"]


def test_and_step():
    s = Steps()
    with s.and_("more"):
        pass
    assert s.passed == ["And: more"]


def test_empty_description_is_rejected():
    with pytest.raises(ValueError):
        with Steps().given(""):
            pass
