<?php

declare(strict_types=1);

namespace SuggestedTests;

/**
 * Compares values to snapshot files stored next to the tests.
 *
 * A missing snapshot is written and the comparison passes, unless running in
 * CI (`$CI` is set), where it fails instead. Set
 * `SUGGESTEDTESTS_UPDATE_SNAPSHOTS=1` to rewrite snapshots that differ.
 * Non-string values are stored as pretty-printed JSON.
 */
final class Snapshot
{
    public const UPDATE_ENV = 'SUGGESTEDTESTS_UPDATE_SNAPSHOTS';

    private function __construct()
    {
    }

    /** The text stored for `$value`. */
    /** @param mixed $value */
    public static function serialize($value): string
    {
        if (is_string($value)) {
            return $value;
        }
        return json_encode(
            $value,
            JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR
        ) . "\n";
    }

    /**
     * Compares `$value` to the snapshot at `$path`.
     *
     * @param mixed $value
     * @return bool Whether a new snapshot was written.
     */
    public static function assertMatches($value, string $path): bool
    {
        $actual = self::serialize($value);
        if (!is_file($path)) {
            if (getenv('CI') !== false && getenv(self::UPDATE_ENV) === false) {
                Failure::raise("Snapshot $path does not exist. Run the tests locally to create it, then commit it.");
            }
            self::write($path, $actual);
            return true;
        }
        $expected = (string) file_get_contents($path);
        if ($expected === $actual) {
            return false;
        }
        if (in_array(getenv(self::UPDATE_ENV), ['1', 'true'], true)) {
            self::write($path, $actual);
            return true;
        }
        if (class_exists(\SebastianBergmann\Comparator\ComparisonFailure::class)) {
            throw new \PHPUnit\Framework\ExpectationFailedException(
                "Value does not match snapshot $path (set " . self::UPDATE_ENV . '=1 to update it)',
                new \SebastianBergmann\Comparator\ComparisonFailure($expected, $actual, $expected, $actual)
            );
        }
        Failure::raise("Value does not match snapshot $path (set " . self::UPDATE_ENV . "=1 to update it)\n--- expected\n$expected\n+++ actual\n$actual");
    }

    private static function write(string $path, string $contents): void
    {
        $dir = dirname($path);
        if (!is_dir($dir) && !mkdir($dir, 0777, true) && !is_dir($dir)) {
            throw new \RuntimeException("cannot create $dir");
        }
        file_put_contents($path, $contents);
    }
}
