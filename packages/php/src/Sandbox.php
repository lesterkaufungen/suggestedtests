<?php

declare(strict_types=1);

namespace SuggestedTests;

/** Runs code with temporary global state that is always restored. */
final class Sandbox
{
    private function __construct()
    {
    }

    /**
     * Runs `$body` with environment variables set (`null` unsets one), then
     * restores them, also in `$_ENV` and `$_SERVER`.
     *
     * ```php
     * Sandbox::withEnv(['APP_ENV' => 'production'], fn () => $this->assertTrue(isProduction()));
     * ```
     *
     * @template T
     * @param array<string, ?string> $vars
     * @param callable(): T $body
     * @return T
     */
    public static function withEnv(array $vars, callable $body)
    {
        $saved = [];
        foreach ($vars as $name => $value) {
            if ($name === '' || Compat::contains($name, '=')) {
                throw new \InvalidArgumentException("invalid environment variable name '$name'");
            }
            $saved[$name] = [getenv($name), $_ENV[$name] ?? null, $_SERVER[$name] ?? null];
        }
        try {
            foreach ($vars as $name => $value) {
                self::setEnv($name, $value === null ? false : $value, $value, $value);
            }
            return $body();
        } finally {
            foreach ($saved as $name => [$env, $envArray, $server]) {
                self::setEnv($name, $env, $envArray, $server);
            }
        }
    }

    /** @param string|false $env */
    private static function setEnv(string $name, $env, ?string $envArray, ?string $server): void
    {
        putenv($env === false ? $name : "$name=$env");
        if ($envArray === null) {
            unset($_ENV[$name]);
        } else {
            $_ENV[$name] = $envArray;
        }
        if ($server === null) {
            unset($_SERVER[$name]);
        } else {
            $_SERVER[$name] = $server;
        }
    }

    /**
     * Runs `$body` with ini settings changed, then restores them.
     *
     * @template T
     * @param array<string, string|int|float|bool> $settings
     * @param callable(): T $body
     * @return T
     */
    public static function withIni(array $settings, callable $body)
    {
        $saved = [];
        try {
            foreach ($settings as $name => $value) {
                $value = is_bool($value) ? ($value ? '1' : '0') : (string) $value;
                $old = ini_set($name, $value);
                if ($old === false) {
                    throw new \InvalidArgumentException("ini setting '$name' can't be changed at runtime");
                }
                $saved[$name] = $old;
            }
            return $body();
        } finally {
            foreach (array_reverse($saved, true) as $name => $old) {
                ini_set($name, $old);
            }
        }
    }

    /** Runs `$body` and returns everything it echoed or printed. */
    public static function captureOutput(callable $body): string
    {
        ob_start();
        $level = ob_get_level();
        try {
            $body();
        } finally {
            while (ob_get_level() > $level) {
                ob_end_flush();
            }
            $output = (string) ob_get_clean();
        }
        return $output;
    }

    /**
     * Creates an empty directory under the system temp dir.
     * Delete it with {@see removeDirectory()}.
     */
    public static function temporaryDirectory(string $prefix = 'suggestedtests-'): string
    {
        for ($i = 0; $i < 10; $i++) {
            $dir = sys_get_temp_dir() . DIRECTORY_SEPARATOR . $prefix . bin2hex(random_bytes(6));
            if (@mkdir($dir, 0700)) {
                return $dir;
            }
        }
        throw new \RuntimeException('cannot create a temporary directory in ' . sys_get_temp_dir());
    }

    /** Recursively deletes `$dir`. Does nothing if it doesn't exist. */
    public static function removeDirectory(string $dir): void
    {
        if (!file_exists($dir) && !is_link($dir)) {
            return;
        }
        if (is_link($dir) || !is_dir($dir)) {
            unlink($dir);
            return;
        }
        $items = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($dir, \FilesystemIterator::SKIP_DOTS),
            \RecursiveIteratorIterator::CHILD_FIRST
        );
        foreach ($items as $item) {
            /** @var \SplFileInfo $item */
            if ($item->isDir() && !$item->isLink()) {
                rmdir($item->getPathname());
            } else {
                unlink($item->getPathname());
            }
        }
        rmdir($dir);
    }
}
