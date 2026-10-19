<?php

declare(strict_types=1);

namespace SuggestedTests\Native;

use SuggestedTests\Compat;

/**
 * ext-ffi bindings to the Rust bridge in the monorepo's `native/`. Mirrors
 * `native/include/suggestedtests_native.h`; keep the two in sync.
 *
 * The library is looked up, in order, at:
 *  1. `$SUGGESTEDTESTS_NATIVE_LIB` (an explicit path, e.g. a local cargo build),
 *  2. `native/prebuilt/<platform>/` of this package (installed via Composer),
 *  3. `native/prebuilt/<platform>/` of the monorepo (development checkout).
 *
 * @internal
 */
final class Bridge
{
    public const ABI_VERSION = 1;
    public const OK = 0;
    public const ERR_NULL = -1;
    public const ERR_UNSUPPORTED = -2;
    public const ERR_UNKNOWN = -3;
    public const ENV_VAR = 'SUGGESTEDTESTS_NATIVE_LIB';
    /** Read by the bridge when it loads: turns its startup report on. */
    public const VERBOSE_ENV_VAR = 'SUGGESTEDTESTS_VERBOSE';

    private const CDEF = 'typedef struct StCpuTime { uint64_t user_ns; uint64_t system_ns; } StCpuTime;'
        . 'typedef struct StMemory { uint64_t current_rss_bytes; uint64_t peak_rss_bytes; } StMemory;'
        . 'uint32_t st_abi_version(void);'
        . 'int32_t st_process_cpu_time(StCpuTime *out);'
        . 'int32_t st_thread_cpu_time_ns(uint64_t *out);'
        . 'int32_t st_memory_usage(StMemory *out);'
        . 'uint32_t st_cpu_count(void);'
        . 'uint32_t st_set_verbose(uint32_t verbose);'
        . 'uint32_t st_verbose(void);';

    /** The program interpreter (`PT_INTERP`) of a little-endian ELF file (32 or 64-bit). */
    public static function elfInterpreter(string $path): ?string
    {
        $f = @fopen($path, 'rb');
        if ($f === false) {
            return null;
        }
        try {
            $header = fread($f, 64);
            if ($header === false || strlen($header) < 52 || !Compat::startsWith($header, "\x7fELF")
                || !in_array(ord($header[4]), [1, 2], true) || ord($header[5]) !== 1) {
                return null;
            }
            $is64 = ord($header[4]) === 2;
            if ($is64) {
                $phOffset = unpack('P', $header, 0x20)[1];
                ['size' => $phSize, 'count' => $phCount] = unpack('vsize/vcount', $header, 0x36);
            } else {
                $phOffset = unpack('V', $header, 0x1C)[1];
                ['size' => $phSize, 'count' => $phCount] = unpack('vsize/vcount', $header, 0x2A);
            }
            for ($i = 0; $i < $phCount; $i++) {
                fseek($f, $phOffset + $i * $phSize);
                $ph = fread($f, $phSize);
                if ($ph === false || strlen($ph) < 32 || unpack('V', $ph)[1] !== 3) { // PT_INTERP
                    continue;
                }
                $offset = $is64 ? unpack('P', $ph, 8)[1] : unpack('V', $ph, 4)[1];
                $size = $is64 ? unpack('P', $ph, 32)[1] : unpack('V', $ph, 16)[1];
                fseek($f, $offset);
                $bytes = fread($f, max(1, min($size, 4096)));
                if ($bytes === false) {
                    return null;
                }
                $end = strpos($bytes, "\0");
                return $end === false ? $bytes : substr($bytes, 0, $end);
            }
            return null;
        } finally {
            fclose($f);
        }
    }

    /** Whether PHP runs on Android (e.g. Termux). */
    private static function isAndroid(): bool
    {
        return PHP_OS_FAMILY === 'Linux' && getenv('ANDROID_ROOT') !== false && is_file('/system/build.prop');
    }

    private static function usesMusl(): bool
    {
        // A library built for one libc can't be loaded into a process using
        // the other, so ask the running php executable.
        $interpreter = self::elfInterpreter(PHP_BINARY);
        if ($interpreter !== null) {
            return Compat::contains($interpreter, 'musl');
        }
        return glob('/lib/ld-musl-*') !== [];
    }

    /** `<os>-<arch>[-musl]`, the prebuilt directory for this process, or null. */
    public static function platformDir(): ?string
    {
        return self::platformDirFor(PHP_OS_FAMILY, php_uname('m'), PHP_INT_SIZE, self::isAndroid(), [self::class, 'usesMusl']);
    }

    /**
     * The prebuilt directory for an OS family / machine / int size, or null.
     *
     * @param callable(): bool $usesMusl
     */
    public static function platformDirFor(string $family, string $machine, int $intSize, bool $android, callable $usesMusl): ?string
    {
        $arches = [
            'x86_64' => 'x64', 'amd64' => 'x64', 'aarch64' => 'arm64', 'arm64' => 'arm64',
            'i386' => 'x86', 'i486' => 'x86', 'i586' => 'x86', 'i686' => 'x86', 'x86' => 'x86',
            'armv7l' => 'arm', 'armv7' => 'arm', 'armv8l' => 'arm', 'arm' => 'arm', 'riscv64' => 'riscv64',
        ];
        $arch = $arches[strtolower($machine)] ?? null;
        if ($arch === null) {
            return null;
        }
        if ($intSize === 4) { // a 32-bit PHP on a 64-bit OS
            $arch = ['x64' => 'x86', 'arm64' => 'arm'][$arch] ?? $arch;
        }
        if ($android) {
            $abi = ['arm64' => 'arm64-v8a', 'arm' => 'armeabi-v7a', 'x64' => 'x86_64', 'x86' => 'x86'][$arch] ?? null;
            return $abi === null ? null : "android-$abi";
        }
        switch ($family) {
            case 'Linux':
                return "linux-$arch" . ($usesMusl() ? '-musl' : '');
            case 'Darwin':
                return "macos-$arch";
            case 'Windows':
                return "windows-$arch";
            default:
                return null;
        }
    }

    /** The bridge's file name on this OS. */
    public static function libraryFileName(): string
    {
        switch (PHP_OS_FAMILY) {
            case 'Windows':
                return 'suggestedtests_native.dll';
            case 'Darwin':
                return 'libsuggestedtests_native.dylib';
            default:
                return 'libsuggestedtests_native.so';
        }
    }

    /** @return list<string> Paths the library is looked up at, in order. */
    public static function candidates(): array
    {
        $explicit = getenv(self::ENV_VAR);
        if (is_string($explicit) && $explicit !== '') {
            return [$explicit];
        }
        $dir = self::platformDir();
        if ($dir === null) {
            return [];
        }
        $name = self::libraryFileName();
        $package = dirname(__DIR__, 2); // src/Native -> package root
        return [
            "$package/native/prebuilt/$dir/$name",
            dirname($package, 2) . "/native/prebuilt/$dir/$name",
        ];
    }

    /**
     * Loads the library.
     *
     * @throws \RuntimeException if ext-ffi is unusable or the library is missing.
     */
    public static function load(): \FFI
    {
        if (!extension_loaded('ffi')) {
            throw new \RuntimeException('ext-ffi is not loaded');
        }
        $enabled = strtolower((string) ini_get('ffi.enable'));
        if (!in_array($enabled, ['1', 'on', 'true', 'yes'], true)
            && !($enabled === 'preload' && PHP_SAPI === 'cli')) {
            throw new \RuntimeException("ffi.enable=$enabled does not allow FFI here");
        }
        $paths = self::candidates();
        if ($paths === []) {
            throw new \RuntimeException(sprintf('no prebuilt bridge for %s/%s', PHP_OS_FAMILY, php_uname('m')));
        }
        foreach ($paths as $path) {
            if (is_file($path)) {
                $ffi = \FFI::cdef(self::CDEF, $path);
                self::tryOnLoad($path);
                return $ffi;
            }
        }
        throw new \RuntimeException('bridge library not found at: ' . implode(', ', $paths));
    }

    /**
     * Calls `st_on_load`, best-effort. Declared in a `cdef()` of its own:
     * `FFI::cdef()` resolves every symbol in a single call eagerly and
     * throws for the whole call if even one is missing, so this additive
     * (no ABI bump) symbol can't share `self::CDEF` without an older
     * prebuilt that predates it making the whole bridge look unavailable.
     */
    private static function tryOnLoad(string $path): void
    {
        try {
            \FFI::cdef('void st_on_load(void);', $path)->st_on_load();
        } catch (\Throwable $e) {
            // Ignored.
        }
    }
}
