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
