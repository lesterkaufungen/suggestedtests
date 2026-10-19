import pytest
from suggestedtests import MiB, expect_memory


@pytest.mark.requires_native_bridge
def test_import_stays_under_50_mib():
    with expect_memory(max_peak_growth=50 * MiB):
        importer.run(big_file)
