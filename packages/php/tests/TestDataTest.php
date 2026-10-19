<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;
use SuggestedTests\PHPUnit\SuggestedTests;
use SuggestedTests\TestData;

final class TestDataTest extends TestCase
{
    use SuggestedTests;

    public function testSameSeedSameValues(): void
    {
        $a = new TestData(42);
        $b = new TestData(42);
        $this->assertSame([$a->integer(), $a->email(), $a->uuid()], [$b->integer(), $b->email(), $b->uuid()]);
    }

    public function testRanges(): void
    {
        $d = new TestData(1);
        $seen = [];
        for ($i = 0; $i < 300; $i++) {
            $n = $d->integer(3, 5);
            $seen[$n] = true;
            $f = $d->decimal(1.0, 2.0);
            $this->assertTrue($f >= 1.0 && $f < 2.0);
        }
        ksort($seen);
        $this->assertSame([3, 4, 5], array_keys($seen));
    }

    public function testStrings(): void
    {
        $d = new TestData(2);
        $this->assertSame(12, strlen($d->string(12)));
        $this->assertMatchesRegularExpression('/^[ab]{50}$/', $d->string(50, 'ab'));
        $this->assertMatchesRegularExpression('/^(?:ä|ö){4}$/u', $d->string(4, 'äö'));
        $this->assertMatchesRegularExpression('/^[A-Z][a-z]+( [a-z]+){5}\.$/', $d->sentence());
        $this->assertMatchesRegularExpression('/^[a-z]+\.[a-z]{5}@example\.com$/', $d->email());
        $this->assertMatchesRegularExpression('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/', $d->uuid());
    }

    public function testDatesAndCollections(): void
    {
        $d = new TestData(3);
        $from = new \DateTimeImmutable('2020-01-01T00:00:00Z');
        $to = new \DateTimeImmutable('2020-02-01T00:00:00Z');
        $date = $d->date($from, $to);
        $this->assertTrue($date >= $from && $date <= $to);
        $this->assertSame('UTC', $date->getTimezone()->getName());
        $this->assertContains($d->pick(['x' => 1, 'y' => 2]), [1, 2]);
        $this->assertCount(3, $d->listOf(3, fn (TestData $g) => $g->word()));
        $shuffled = $d->shuffled(new \ArrayIterator([1, 2, 3, 4]));
        sort($shuffled);
        $this->assertSame([1, 2, 3, 4], $shuffled);
    }

    /** @return iterable<string, array{\Closure(TestData): mixed, class-string<\Throwable>}> */
    public static function invalidCalls(): iterable
    {
        yield 'integer' => [fn (TestData $d) => $d->integer(5, 1), \InvalidArgumentException::class];
        yield 'decimal' => [fn (TestData $d) => $d->decimal(2, 1), \InvalidArgumentException::class];
        yield 'boolean' => [fn (TestData $d) => $d->boolean(2), \OutOfRangeException::class];
        yield 'string length' => [fn (TestData $d) => $d->string(-1), \OutOfRangeException::class];
        yield 'empty alphabet' => [fn (TestData $d) => $d->string(3, ''), \InvalidArgumentException::class];
        yield 'sentence' => [fn (TestData $d) => $d->sentence(0), \OutOfRangeException::class];
        yield 'pick' => [fn (TestData $d) => $d->pick([]), \InvalidArgumentException::class];
        yield 'listOf' => [fn (TestData $d) => $d->listOf(-1, fn () => 1), \OutOfRangeException::class];
        yield 'date' => [fn (TestData $d) => $d->date(new \DateTimeImmutable('2021-01-01'), new \DateTimeImmutable('2020-01-01')), \InvalidArgumentException::class];
    }

    /** @param class-string<\Throwable> $exception */
    /** @dataProvider invalidCalls */
    #[DataProvider('invalidCalls')]
    public function testValidatesArguments(\Closure $call, string $exception): void
    {
        $this->expectException($exception);
        $call(new TestData());
    }

    public function testTraitDataIsStableWithinATest(): void
    {
        $this->assertSame($this->testData(), $this->testData());
    }

    public function testSeedFromEnvironment(): void
    {
        putenv('SUGGESTEDTESTS_SEED=1234');
        try {
            $this->assertSame(1234, $this->testData()->seed);
        } finally {
            putenv('SUGGESTEDTESTS_SEED');
        }
    }

    public function testRandomSeedIsReproducible(): void
    {
        $d = TestData::randomSeed();
        $this->assertSame((new TestData($d->seed))->integer(), $d->integer());
    }
}
