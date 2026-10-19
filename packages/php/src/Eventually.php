<?php

declare(strict_types=1);

namespace SuggestedTests;

/** Polling assertions that replace fixed sleeps. */
final class Eventually
{
    private function __construct()
    {
    }

    /**
     * Re-runs `$body` every `$intervalMs` until it returns without throwing,
     * then returns its result. Fails with the last error after `$timeoutMs`.
     *
     * ```php
     * Eventually::until(fn () => $this->assertFileExists($exportPath));
     * ```
     *
     * @template T
     * @param callable(): T $body
     * @return T
     */
    public static function until(callable $body, float $timeoutMs = 5000, float $intervalMs = 20)
    {
        if ($timeoutMs < 0) {
            throw new \OutOfRangeException("timeoutMs must be >= 0, got $timeoutMs");
        }
        if ($intervalMs < 0) {
            throw new \OutOfRangeException("intervalMs must be >= 0, got $intervalMs");
        }
        $start = hrtime(true);
        $attempts = 0;
        while (true) {
            $attempts++;
            try {
                return $body();
            } catch (\Throwable $error) {
                if ((hrtime(true) - $start) / 1e6 >= $timeoutMs) {
                    Failure::raise(sprintf(
                        "Condition not met within %s (%d attempts). Last error:\n%s",
                        Format::ms($timeoutMs),
                        $attempts,
                        $error->getMessage()
                    ), $error);
                }
            }
            usleep((int) ($intervalMs * 1000));
        }
    }
}
