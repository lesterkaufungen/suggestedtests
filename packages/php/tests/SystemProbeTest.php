<?php

declare(strict_types=1);

namespace SuggestedTests\Tests;

use PHPUnit\Framework\TestCase;
use SuggestedTests\CpuTime;
use SuggestedTests\Format;
use SuggestedTests\MemoryUsage;
use SuggestedTests\Native\Bridge;
use SuggestedTests\NativeBridgeException;
use SuggestedTests\PHPUnit\SuggestedTests;
use SuggestedTests\SystemProbe;

final class SystemProbeTest extends TestCase
{
    use SuggestedTests;

    private static function burn(): int
    {
        $x = 0;
        for ($i = 0; $i < 100_000; $i++) {
            $x = ($x * 31 + $i) % 1_000_003;
        }
        return $x;
    }

    public function testFormat(): void
    {
        $this->assertSame('0 B', Format::bytes(0));
        $this->assertSame('1.5 KiB', Format::bytes(1536));
        $this->assertSame('5.0 MiB', Format::bytes(5 * 1024 ** 2));
        $this->assertSame('-2.0 KiB', Format::bytes(-2048));
        $this->assertSame('850µs', Format::ms(0.85));
        $this->assertSame('1.25ms', Format::ms(1.25));
        $this->assertSame('2.00s', Format::ms(2000));
    }

    public function testCpuTimeArithmetic(): void
    {
        $d = (new CpuTime(30, 7))->minus(new CpuTime(10, 2));
        $this->assertSame([20, 5, 25], [$d->userNs, $d->systemNs, $d->totalNs()]);
    }

    public function testExceptionExplainsStatus(): void
    {
        $this->assertStringContainsString('not supported on this OS', (new NativeBridgeException('x', Bridge::ERR_UNSUPPORTED))->getMessage());
        $this->assertStringContainsString('OS error 13', (new NativeBridgeException('x', 13))->getMessage());
    }

    public function testPlatformIsKnown(): void
    {
        $this->assertNotNull(Bridge::platformDir());
    }

    public function testPlatformDirMapping(): void
    {
        $glibc = static function (): bool {
            return false;
        };
        $musl = static function (): bool {
            return true;
        };
        $this->assertSame('linux-x64', Bridge::platformDirFor('Linux', 'x86_64', 8, false, $glibc));
        $this->assertSame('linux-x64-musl', Bridge::platformDirFor('Linux', 'x86_64', 8, false, $musl));
        $this->assertSame('linux-x86', Bridge::platformDirFor('Linux', 'i686', 4, false, $glibc));
        $this->assertSame('linux-arm', Bridge::platformDirFor('Linux', 'armv7l', 4, false, $glibc));
        $this->assertSame('linux-riscv64', Bridge::platformDirFor('Linux', 'riscv64', 8, false, $glibc));
        $this->assertSame('windows-x86', Bridge::platformDirFor('Windows', 'AMD64', 4, false, $glibc));
        $this->assertSame('macos-arm64', Bridge::platformDirFor('Darwin', 'arm64', 8, false, $glibc));
        $this->assertSame('android-arm64-v8a', Bridge::platformDirFor('Linux', 'aarch64', 8, true, $glibc));
        $this->assertNull(Bridge::platformDirFor('Linux', 'mips', 4, false, $glibc));
    }

    public function testElfInterpreterReads32And64Bit(): void
    {
        foreach ([[1, "/lib/ld-musl-armhf.so.1"], [2, "/lib64/ld-linux-x86-64.so.2"]] as [$class, $interp]) {
            $is64 = $class === 2;
            [$ehsize, $phsize] = $is64 ? [64, 56] : [52, 32];
            $text = $interp . "\0";
            $header = str_pad("\x7fELF" . chr($class) . chr(1), $ehsize, "\0");
            if ($is64) {
                $header = substr_replace($header, pack('P', $ehsize), 0x20, 8);
                $header = substr_replace($header, pack('vv', $phsize, 1), 0x36, 4);
                $ph = pack('VVPPPPPP', 3, 4, $ehsize + $phsize, 0, 0, strlen($text), strlen($text), 1);
            } else {
                $header = substr_replace($header, pack('V', $ehsize), 0x1C, 4);
                $header = substr_replace($header, pack('vv', $phsize, 1), 0x2A, 4);
                $ph = pack('VVVVVVVV', 3, $ehsize + $phsize, 0, 0, strlen($text), strlen($text), 4, 1);
            }
            $file = $this->temporaryDirectory() . "/elf$class";
            file_put_contents($file, $header . $ph . $text);
            $this->assertSame($interp, Bridge::elfInterpreter($file));
        }
    }

    public function testElfInterpreterOfNonElfIsNull(): void
    {
        $this->assertNull(Bridge::elfInterpreter(__FILE__));
        $this->assertNull(Bridge::elfInterpreter('/does/not/exist'));
    }

    public function testExplicitPathWins(): void
    {
        putenv(Bridge::ENV_VAR . '=/nope/missing.so');
        try {
            $this->assertSame(['/nope/missing.so'], Bridge::candidates());
            SystemProbe::reset();
            $this->assertFalse(SystemProbe::isAvailable());
            $this->assertStringContainsString('missing.so', (string) SystemProbe::skipReason());
            $this->expectException(NativeBridgeException::class);
            SystemProbe::memoryUsage();
        } finally {
            putenv(Bridge::ENV_VAR);
            SystemProbe::reset();
        }
    }

    public function testProcessCpuTimeAdvances(): void
    {
        $this->requireNativeBridge();
        $before = SystemProbe::processCpuTime();
        while (SystemProbe::processCpuTime()->minus($before)->totalNs() <= 0) {
            self::burn();
        }
        $this->addToAssertionCount(1);
    }

    public function testThreadCpuTimeAdvances(): void
    {
        $this->requireNativeBridge();
        $before = SystemProbe::threadCpuTimeNs();
        while (SystemProbe::threadCpuTimeNs() <= $before) {
            self::burn();
        }
        $this->addToAssertionCount(1);
    }

    public function testMemoryUsageIsPlausible(): void
    {
        $this->requireNativeBridge();
        $m = SystemProbe::memoryUsage();
        $this->assertInstanceOf(MemoryUsage::class, $m);
        $this->assertGreaterThan(1024 * 1024, $m->currentRssBytes);
        $this->assertGreaterThanOrEqual($m->currentRssBytes, $m->peakRssBytes);
        $this->assertStringContainsString('MiB', (string) $m);
        $this->assertGreaterThanOrEqual(1, SystemProbe::cpuCount());
    }

    /**
     * Runs `$code` in a fresh PHP process (the report goes to its stderr).
     *
     * @param array<string, string> $env
     * @return array{0: string, 1: string} stdout and stderr
     */
    private function runChild(string $code, array $env = []): array
    {
        $environ = getenv();
        unset($environ[Bridge::VERBOSE_ENV_VAR]);
        // The autoloader running this test (vendor/composer/ClassLoader.php).
        $loader = (string) (new \ReflectionClass(\Composer\Autoload\ClassLoader::class))->getFileName();
        $autoload = var_export(dirname($loader, 2) . '/autoload.php', true);
        $script = "require {$autoload}; use SuggestedTests\\SystemProbe; {$code}";
        $pipes = [];
        $process = proc_open(
            [PHP_BINARY, '-d', 'ffi.enable=1', '-r', $script],
            [1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
            $pipes,
            null,
            $env + $environ
        );
        $this->assertIsResource($process);
        $out = (string) stream_get_contents($pipes[1]);
        $err = (string) stream_get_contents($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        $this->assertSame(0, proc_close($process), $out . $err);
        return [$out, $err];
    }

    public function testBridgeIsSilentByDefault(): void
    {
        $this->requireNativeBridge();
        [$out, $err] = $this->runChild('var_export(SystemProbe::verbose());');
        $this->assertSame('false', $out);
        $this->assertStringNotContainsString('suggestedtests:', $err);
    }

    public function testEnvVarPrintsTheReportWhenTheBridgeLoads(): void
    {
        $this->requireNativeBridge();
        [$out, $err] = $this->runChild('var_export(SystemProbe::verbose());', [Bridge::VERBOSE_ENV_VAR => '1']);
        $this->assertSame('true', $out);
        $this->assertSame(1, substr_count($err, 'suggestedtests: platform: '), $err);
        $this->assertStringContainsString('suggestedtests: environment: ', $err);
    }

    public function testTheAutoloaderAloneLoadsTheBridge(): void
    {
        $this->requireNativeBridge();
        [, $err] = $this->runChild('', [Bridge::VERBOSE_ENV_VAR => '1']);
        $this->assertSame(1, substr_count($err, 'suggestedtests: platform: '), $err);
    }

    public function testSetVerbosePrintsTheReportOnce(): void
    {
        $this->requireNativeBridge();
        [$out, $err] = $this->runChild(
            'echo json_encode([SystemProbe::verbose(), SystemProbe::setVerbose(true),'
            . ' SystemProbe::setVerbose(true), SystemProbe::setVerbose(false), SystemProbe::verbose()]);'
        );
        $this->assertSame('[false,false,true,true,false]', $out);
        $this->assertSame(1, substr_count($err, 'suggestedtests: platform: '), $err);
    }
}
