<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\AssertionFailedError;
use PHPUnit\Framework\TestCase;
use SuggestedTests\PHPUnit\SuggestedTests;
use SuggestedTests\Spy;

final class SpyTest extends TestCase
{
    use SuggestedTests;

    public function testRecordsAndDelegates(): void
    {
        $spy = new Spy(fn (int $a, int $b) => $a + $b);
        $this->assertSpyNotCalled($spy);
        $this->assertSame(5, $spy(2, 3));
        $spy(1, 1);
        $this->assertSame([[2, 3], [1, 1]], $spy->calls());
        $this->assertSame([1, 1], $spy->lastCall());
        $this->assertSpyCalled($spy);
        $this->assertSpyCalledTimes($spy, 2);
        $this->assertSpyCalledWith($spy, [2, 3]);
        $this->assertSpyCalledWith($spy, [$this->greaterThan(0), 1]);
        $spy->reset();
        $this->assertCount(0, $spy);
    }

    public function testWorksAsCallable(): void
    {
        $spy = new Spy();
        array_map($spy, ['a', 'b']);
        $this->assertSpyCalledWith($spy, ['b']);
        $this->assertNull($spy('x'));
    }

    public function testCalledWithFailureListsCalls(): void
    {
        $spy = new Spy();
        $spy('hello');
        try {
            $this->assertSpyCalledWith($spy, ['bye']);
        } catch (AssertionFailedError $e) {
            $this->assertStringContainsString('Expected the spy to be called with ["bye"], but it was called 1 time(s): Spy(calls: [["hello"]])', $e->getMessage());
            return;
        }
        $this->fail('expected a failure');
    }

    public function testLastCallOfUnusedSpyThrows(): void
    {
        $this->expectException(\LogicException::class);
        (new Spy())->lastCall();
    }
}
