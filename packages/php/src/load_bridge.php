<?php

// Included by Composer's autoloader ("autoload.files" in composer.json): loads
// the native bridge right away, so its startup report (SUGGESTEDTESTS_VERBOSE=1)
// is printed even in runs that never call a native helper. CLI only, which is
// where PHPUnit runs; it never throws: where the bridge is unavailable,
// SystemProbe says why when it is used.

declare(strict_types=1);

if (PHP_SAPI === 'cli') {
    \SuggestedTests\SystemProbe::isAvailable();
}
