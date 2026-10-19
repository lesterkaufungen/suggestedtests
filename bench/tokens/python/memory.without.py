import resource
import sys


def _peak_rss_bytes():
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return peak if sys.platform == "darwin" else peak * 1024


def test_import_stays_under_50_mib():
    before = _peak_rss_bytes()
    importer.run(big_file)
    growth = _peak_rss_bytes() - before
    assert growth <= 50 * 1024 * 1024, f"peak RSS grew by {growth / 1048576:.1f} MiB > 50 MiB"
