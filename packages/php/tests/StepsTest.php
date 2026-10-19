<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\ExpectationFailedException;
use PHPUnit\Framework\TestCase;
use SuggestedTests\PHPUnit\SuggestedTests;
use SuggestedTests\Steps;

final class StepsTest extends TestCase
{
    use SuggestedTests;

    public function testRunsStepsInOrder(): void
    {
        $log = [];
        $this->scenario(function (Steps $s) use (&$log) {
            $s->given('a', function () use (&$log) { $log[] = 'a'; });
            $s->when('b', function () use (&$log) { $log[] = 'b'; });
            // Arrow functions capture by value, so read $log through a reference.
            $s->then('c', function () use (&$log) { $this->assertSame(['a', 'b'], $log); });
            $s->and('d', function () use (&$log) { $this->assertCount(2, $log); });
        });
    }

    public function testFailureKeepsClassAndNamesStep(): void
    {
        $ran = false;
        $steps = (new Steps())
            ->given('setup', fn () => null)
            ->then('the total is 30', fn () => $this->assertSame(30, 20))
            ->and('never', function () use (&$ran) { $ran = true; });
        try {
            $steps->run();
        } catch (ExpectationFailedException $e) {
            $this->assertStringStartsWith("Then: the total is 30\nFailed asserting that 20 is identical to 30.", $e->getMessage());
            $this->assertFalse($ran);
            return;
        }
        $this->fail('expected the original failure');
    }

    public function testErrorsArePrefixedToo(): void
    {
        $this->expectException(\TypeError::class);
        $this->expectExceptionMessageMatches('/^When: it breaks\nboom/');
        (new Steps())->when('it breaks', function () {
            throw new \TypeError('boom');
        })->run();
    }

    public function testValidates(): void
    {
        $this->expectException(\LogicException::class);
        (new Steps())->run();
    }

    public function testEmptyDescriptionIsRejected(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        (new Steps())->given('', fn () => null);
    }
}
