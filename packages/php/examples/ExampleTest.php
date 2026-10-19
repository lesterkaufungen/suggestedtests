<?php

declare(strict_types=1);

namespace SuggestedTests\Examples;

use PHPUnit\Framework\TestCase;
use SuggestedTests\Benchmark;
use SuggestedTests\Clock;
use SuggestedTests\Memory;
use SuggestedTests\PHPUnit\SuggestedTests;
use SuggestedTests\Sandbox;
use SuggestedTests\Spy;
use SuggestedTests\Steps;
use SuggestedTests\SystemProbe;

/** A tour of suggestedtests. Run it with: vendor/bin/phpunit examples */
final class ExampleTest extends TestCase
{
    use SuggestedTests;

    public function testGivenWhenThen(): void
    {
        $this->scenario(function (Steps $s) {
            $items = [];
            $s->given('an empty cart', function () use (&$items) { $items = []; });
            $s->when('two items are added', function () use (&$items) { $items[] = 10; $items[] = 20; });
            $s->then('the total is 30', function () use (&$items) { $this->assertSame(30, array_sum($items)); });
        });
    }

    public function testSeededDataIsUnique(): void
    {
        $ids = $this->testData()->listOf(100, fn ($d) => $d->uuid());
        $this->assertUniqueElements($ids);
    }

    public function testEncodingStaysFast(): void
    {
        $payload = range(1, 1000);
        $result = $this->assertPerformance(fn () => json_encode($payload), 50);
        $this->assertGreaterThan(0, $result->median());
    }

    public function testCpuTimeIgnoresWaiting(): void
    {
        $this->requireNativeBridge();
        $result = Benchmark::run('sleep', fn () => usleep(1000), 3, 3, Clock::Cpu);
        $this->assertLessThan(1, $result->median());
        $this->assertGreaterThanOrEqual(1, SystemProbe::cpuCount());
    }

    public function testBuildingRowsStaysUnderBudget(): void
    {
        $this->assertMemory(fn () => array_fill(0, 1000, ['id' => 1]), 1 * Memory::MiB);
    }

    public function testCallbackIsCalled(): void
    {
        $onItem = new Spy();
        $fruit = ['apple', 'pear'];
        array_walk($fruit, $onItem);
        $this->assertSpyCalledTimes($onItem, 2);
        $this->assertSpyCalledWith($onItem, ['pear', 1]);
    }

    public function testFileAppearsEventually(): void
    {
        $file = $this->temporaryDirectory() . '/done';
        touch($file);
        $this->assertEventually(fn () => $this->assertFileExists($file));
    }

    public function testRendersTheGreeting(): void
    {
        $html = Sandbox::withEnv(['GREETING' => 'Hello'], fn () => Sandbox::captureOutput(function () {
            echo '<p>' . getenv('GREETING') . ', Ada</p>';
        }));
        $this->assertMatchesSnapshot($html);
    }
}
