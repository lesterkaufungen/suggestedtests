from suggestedtests import expect_performance


def test_parsing_stays_fast():
    expect_performance(lambda: parse(big_json), budget=0.005)
