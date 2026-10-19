<?php

declare(strict_types=1);

namespace SuggestedTests;

/** Assertions PHPUnit doesn't have built in. */
final class Assert
{
    private function __construct()
    {
    }

    /**
     * Fails if `$items` contains two equal elements (`==` for objects and
     * arrays, `===` otherwise), naming the duplicate and both keys.
     *
     * @param iterable<mixed> $items
     */
    public static function unique(iterable $items): void
    {
        $seen = [];
        foreach ($items as $key => $item) {
            foreach ($seen as [$otherKey, $other]) {
                $equal = is_object($item) || is_array($item) ? $item == $other : $item === $other;
                if ($equal) {
                    Failure::raise(sprintf(
                        'Expected unique elements, but %s appears at %s and %s',
                        self::export($item),
                        var_export($otherKey, true),
                        var_export($key, true)
                    ));
                }
            }
            $seen[] = [$key, $item];
        }
    }

    /** @param mixed $value */
    private static function export($value): string
    {
        return is_scalar($value) || $value === null
            ? var_export($value, true)
            : (json_encode($value, JSON_PARTIAL_OUTPUT_ON_ERROR | JSON_UNESCAPED_SLASHES) ?: Compat::typeOf($value));
    }
}
