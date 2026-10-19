<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\AssertionFailedError;
use PHPUnit\Framework\ExpectationFailedException;
use PHPUnit\Framework\TestCase;
use SuggestedTests\PHPUnit\SuggestedTests;
use SuggestedTests\Sandbox;
use SuggestedTests\Snapshot;

final class SnapshotTest extends TestCase
{
    use SuggestedTests;

    public function testSerialize(): void
    {
        $this->assertSame('text', Snapshot::serialize('text'));
        $this->assertSame("{\n    \"a\": 1.0,\n    \"b\": [\n        \"x/y\"\n    ]\n}\n", Snapshot::serialize(['a' => 1.0, 'b' => ['x/y']]));
    }

    public function testCreatesComparesAndUpdates(): void
    {
        $path = $this->temporaryDirectory() . '/snap/value.txt';
        Sandbox::withEnv(['CI' => null, Snapshot::UPDATE_ENV => null], function () use ($path) {
            $this->assertTrue(Snapshot::assertMatches(['n' => 1], $path));
            $this->assertFileExists($path);
            $this->assertFalse(Snapshot::assertMatches(['n' => 1], $path));
            try {
                Snapshot::assertMatches(['n' => 2], $path);
                $this->fail('expected a mismatch');
            } catch (ExpectationFailedException $e) {
                $this->assertStringContainsString('does not match snapshot', $e->getMessage());
                $this->assertStringContainsString('"n": 2', (string) ($e->getComparisonFailure() === null ? '' : $e->getComparisonFailure()->getActualAsString()));
            }
        });
        Sandbox::withEnv([Snapshot::UPDATE_ENV => '1'], fn () => Snapshot::assertMatches(['n' => 2], $path));
        $this->assertStringContainsString('"n": 2', (string) file_get_contents($path));
    }

    public function testMissingSnapshotFailsInCi(): void
    {
        $path = $this->temporaryDirectory() . '/missing.txt';
        $this->expectException(AssertionFailedError::class);
        $this->expectExceptionMessage('does not exist');
        Sandbox::withEnv(['CI' => 'true', Snapshot::UPDATE_ENV => null], fn () => Snapshot::assertMatches('x', $path));
    }

    public function testTraitStoresSnapshotsNextToTheTest(): void
    {
        $this->assertMatchesSnapshot(['greeting' => 'hello']);
        $this->assertMatchesSnapshot('second');
        $this->assertFileExists(__DIR__ . '/__snapshots__/SnapshotTest/testTraitStoresSnapshotsNextToTheTest.txt');
        $this->assertFileExists(__DIR__ . '/__snapshots__/SnapshotTest/testTraitStoresSnapshotsNextToTheTest_2.txt');
    }
}
