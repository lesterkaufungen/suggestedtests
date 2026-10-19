<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\AssertionFailedError;
use PHPUnit\Framework\TestCase;
use SuggestedTests\Eventually;
use SuggestedTests\PHPUnit\SuggestedTests;

final class EventuallyTest extends TestCase
{
    use SuggestedTests;

    public function testReturnsOnceConditionHolds(): void
    {
        $n = 0;
        $result = $this->assertEventually(function () use (&$n) {
            $this->assertGreaterThanOrEqual(3, ++$n);
            return $n;
        }, 5000, 1);
        $this->assertSame(3, $result);
    }

    public function testFailsWithLastError(): void
    {
        try {
            Eventually::until(function () {
                throw new \RuntimeException('boom');
            }, 30);
        } catch (AssertionFailedError $e) {
            $this->assertMatchesRegularExpression('/^Condition not met within 30.00ms \(\d+ attempts\)\. Last error:\nboom$/', $e->getMessage());
            $this->assertInstanceOf(\RuntimeException::class, $e->getPrevious());
            return;
        }
        $this->fail('expected a failure');
    }

    public function testValidates(): void
    {
        $this->expectException(\OutOfRangeException::class);
        Eventually::until(fn () => 1, -1);
    }
}
