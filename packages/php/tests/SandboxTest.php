<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\AssertionFailedError;
use PHPUnit\Framework\TestCase;
use SuggestedTests\Assert;
use SuggestedTests\PHPUnit\SuggestedTests;
use SuggestedTests\Sandbox;

final class SandboxTest extends TestCase
{
    use SuggestedTests;

    public function testWithEnvSetsAndRestores(): void
    {
        putenv('ST_A=old');
        $_ENV['ST_A'] = 'old';
        try {
            $seen = Sandbox::withEnv(['ST_A' => 'new', 'ST_B' => 'b'], fn () => [getenv('ST_A'), $_ENV['ST_A'], getenv('ST_B')]);
            $this->assertSame(['new', 'new', 'b'], $seen);
            $this->assertSame('old', getenv('ST_A'));
            $this->assertSame('old', $_ENV['ST_A']);
            $this->assertFalse(getenv('ST_B'));
            $this->assertArrayNotHasKey('ST_B', $_ENV);
        } finally {
            putenv('ST_A');
            unset($_ENV['ST_A']);
        }
    }

    public function testWithEnvRestoresOnException(): void
    {
        try {
            Sandbox::withEnv(['ST_C' => 'x'], function () {
                throw new \RuntimeException('x');
            });
        } catch (\RuntimeException $e) {
        }
        $this->assertFalse(getenv('ST_C'));
    }

    public function testWithEnvValidatesNames(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        Sandbox::withEnv(['A=B' => 'x'], fn () => null);
    }

    public function testWithIni(): void
    {
        $before = ini_get('precision');
        $this->assertSame('5', Sandbox::withIni(['precision' => 5], fn () => ini_get('precision')));
        $this->assertSame($before, ini_get('precision'));
    }

    public function testWithIniRejectsUnknownSettings(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        Sandbox::withIni(['no.such.setting' => 1], fn () => null);
    }

    public function testCaptureOutput(): void
    {
        $this->assertSame("hello world\n", Sandbox::captureOutput(function () {
            echo 'hello ';
            print "world\n";
        }));
    }

    public function testTemporaryDirectoryIsRemovedAfterTheTest(): void
    {
        $dir = $this->temporaryDirectory();
        mkdir("$dir/a/b", 0777, true);
        file_put_contents("$dir/a/b/c.txt", 'x');
        $this->assertDirectoryExists($dir);
        $this->suggestedTestsCleanUp();
        $this->assertDirectoryDoesNotExist($dir);
    }

    public function testUnique(): void
    {
        $this->assertUniqueElements([1, '1', [1], [2]]);
        try {
            Assert::unique(['a' => 'x', 'b' => 'y', 'c' => 'x']);
        } catch (AssertionFailedError $e) {
            $this->assertSame("Expected unique elements, but 'x' appears at 'a' and 'c'", $e->getMessage());
            return;
        }
        $this->fail('expected a failure');
    }

    public function testUniqueComparesObjectsByValue(): void
    {
        $this->expectException(AssertionFailedError::class);
        $this->expectExceptionMessage('{"id":1} appears at 0 and 1');
        Assert::unique([(object) ['id' => 1], (object) ['id' => 1]]);
    }
}
