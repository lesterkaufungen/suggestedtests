pytest_plugins = ["pytester"]


def test_seed_option_and_failure_report(pytester):
    pytester.makepyfile(
        """
        def test_fails(test_data):
            assert test_data.seed == 0
        """
    )
    result = pytester.runpytest("--st-seed=1234")
    result.assert_outcomes(failed=1)
    result.stdout.fnmatch_lines(["*test_data seed: 1234*", "*--st-seed=1234*"])


def test_marker_is_registered(pytester):
    pytester.makepyfile(
        """
        import pytest

        @pytest.mark.requires_native_bridge
        def test_needs_bridge():
            pass
        """
    )
    result = pytester.runpytest("--strict-markers")
    result.assert_outcomes(passed=1)


def test_marker_skips_without_bridge(pytester, monkeypatch, tmp_path):
    monkeypatch.setenv("SUGGESTEDTESTS_NATIVE_LIB", str(tmp_path / "nope.so"))
    pytester.makepyfile(
        """
        import pytest

        @pytest.mark.requires_native_bridge
        def test_needs_bridge():
            pass
        """
    )
    result = pytester.runpytest_subprocess("-rs")
    result.assert_outcomes(skipped=1)
    result.stdout.fnmatch_lines(["*native bridge is not available*"])


def test_pytest_loads_the_bridge_without_any_import(pytester, monkeypatch):
    monkeypatch.setenv("SUGGESTEDTESTS_VERBOSE", "1")
    pytester.makepyfile(
        """
        def test_plain():
            assert 1 + 1 == 2
        """
    )
    result = pytester.runpytest_subprocess()
    result.assert_outcomes(passed=1)
    assert result.stderr.str().count("suggestedtests: platform: ") == 1, result.stderr.str()


def test_failures_point_at_the_test_not_the_helper(pytester):
    pytester.makepyfile(
        """
        from suggestedtests import assert_unique, eventually, expect_performance

        def test_unique():
            assert_unique(["a", "b", "a"])

        def test_budget():
            expect_performance(lambda: sum(range(10_000)), budget=1e-9, iterations=2)

        def test_eventually():
            def check():
                assert False, "not yet"
            eventually(check, timeout=0.01)
        """
    )
    result = pytester.runpytest()
    result.assert_outcomes(failed=3)
    output = result.stdout.str()
    assert "suggestedtests/assertions.py" not in output, output
    assert "suggestedtests/performance.py" not in output, output
    result.stdout.fnmatch_lines(["*Expected unique elements, but 'a' appears at index 0 and 2"])
    # (pytest < 8 still shows eventually's frame in the chained last error.)
    result.stdout.fnmatch_lines(
        [">       eventually(check, timeout=0.01)", "E       AssertionError: Condition not met *"],
        consecutive=True,
    )
