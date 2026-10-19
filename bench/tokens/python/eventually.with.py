from suggestedtests import eventually


def test_cache_warms_up():
    def warm():
        assert cache.is_warm()

    eventually(warm)
