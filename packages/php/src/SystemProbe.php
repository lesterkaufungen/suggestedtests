<?php

declare(strict_types=1);

namespace SuggestedTests;

use SuggestedTests\Native\Bridge;

/**
 * Process metrics read through the OS-agnostic Rust bridge (Windows, Linux
 * and macOS), via ext-ffi.
 *
 * Check `isAvailable()`, or call `$this->requireNativeBridge()` (from the
 * `SuggestedTests` trait) to skip tests where it isn't:
 *
 * ```php
 * public function testNoLeak(): void
 * {
 *     $this->requireNativeBridge();
 *     ...
 * }
 * ```
 */
final class SystemProbe
{
    /** @var ?\FFI */
    private static $ffi = null;
    /** @var ?string */
    private static $unavailable = null;
    /** @var bool */
    private static $probed = false;

    private function __construct()
    {
    }

    private static function probe(): void
    {
        if (self::$probed) {
            return;
        }
        self::$probed = true;
        try {
            $ffi = Bridge::load();
        } catch (\Throwable $e) {
            self::$unavailable = 'suggestedtests native bridge is not available for this platform ('
                . $e->getMessage() . '). Set $' . Bridge::ENV_VAR . ' to a library built from native/.';
            return;
        }
        $version = $ffi->st_abi_version();
        if ($version !== Bridge::ABI_VERSION) {
            self::$unavailable = "suggestedtests native bridge has ABI v$version, expected v"
                . Bridge::ABI_VERSION . '. Rebuild it.';
            return;
        }
        self::$ffi = $ffi;
    }

    /** Whether the bridge is loaded and has the expected ABI version. */
    public static function isAvailable(): bool
    {
        self::probe();
        return self::$ffi !== null;
    }

    /** `null` when available; otherwise why not. */
    public static function skipReason(): ?string
    {
        self::probe();
        return self::$ffi === null ? self::$unavailable : null;
    }

    private static function ffi(string $operation): \FFI
    {
        self::probe();
        if (self::$ffi === null) {
            throw new NativeBridgeException($operation, Bridge::ERR_UNSUPPORTED, self::$unavailable);
        }
        return self::$ffi;
    }

    private static function check(string $operation, int $status): void
    {
        if ($status !== Bridge::OK) {
            throw new NativeBridgeException($operation, $status);
        }
    }

    /** CPU time used by the whole process so far. */
    public static function processCpuTime(): CpuTime
    {
        $ffi = self::ffi('processCpuTime');
        $out = $ffi->new('StCpuTime');
        self::check('processCpuTime', $ffi->st_process_cpu_time(\FFI::addr($out)));
        return new CpuTime($out->user_ns, $out->system_ns);
    }

    /** CPU time used by the calling OS thread so far, in nanoseconds. */
    public static function threadCpuTimeNs(): int
    {
        $ffi = self::ffi('threadCpuTimeNs');
        $out = $ffi->new('uint64_t');
        self::check('threadCpuTimeNs', $ffi->st_thread_cpu_time_ns(\FFI::addr($out)));
        return $out->cdata;
    }

    /** Current and peak resident memory of the process. */
    public static function memoryUsage(): MemoryUsage
    {
        $ffi = self::ffi('memoryUsage');
        $out = $ffi->new('StMemory');
        self::check('memoryUsage', $ffi->st_memory_usage(\FFI::addr($out)));
        return new MemoryUsage($out->current_rss_bytes, $out->peak_rss_bytes);
    }

    /** Number of logical CPUs available to the process. */
    public static function cpuCount(): int
    {
        return self::ffi('cpuCount')->st_cpu_count();
    }

    /**
     * Turns the bridge's startup report on or off; returns the previous setting.
     *
     * The report is three `suggestedtests: ...` lines on stderr describing the
     * platform and environment (OS, arch, libc, container, VM). It is printed
     * at most once per process; turning verbose on prints it now if it hasn't
     * been printed. Verbose controls nothing else. To get it while the bridge
     * loads, set `SUGGESTEDTESTS_VERBOSE=1` (or `putenv()` it) before the
     * first SystemProbe call.
     *
     * ```php
     * SystemProbe::setVerbose(true);
     * ```
     */
    public static function setVerbose(bool $verbose): bool
    {
        return self::ffi('setVerbose')->st_set_verbose($verbose ? 1 : 0) !== 0;
    }

    /** Whether the bridge's startup report is on (see setVerbose()). */
    public static function verbose(): bool
    {
        return self::ffi('verbose')->st_verbose() !== 0;
    }

    /** @internal Forgets the probe result, for tests of the loader. */
    public static function reset(): void
    {
        self::$ffi = null;
        self::$unavailable = null;
        self::$probed = false;
    }
}
