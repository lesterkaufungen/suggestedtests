<?php

declare(strict_types=1);

namespace SuggestedTests;

/**
 * Seeded random test data. The same seed always produces the same values, on
 * every PHP version (a self-contained xoshiro128** generator, not
 * `mt_rand` or `Random\Randomizer`), so a failing test can be reproduced.
 *
 * ```php
 * $data = new TestData(42);
 * $user = new User($data->word(), $data->email(), $data->integer(18, 90));
 * ```
 *
 * The `SuggestedTests` trait's `testData()` picks a seed per test and prints
 * it when the test fails. Needs 64-bit PHP.
 */
final class TestData
{
    /** The default alphabet of {@see string()}. */
    public const ALPHANUMERIC = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    private const LOWER = 'abcdefghijklmnopqrstuvwxyz';
    private const MASK = 0xFFFFFFFF;
    private const WORDS = [
        'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel', 'india',
        'juliet', 'kilo', 'lima', 'mike', 'november', 'oscar', 'papa', 'quebec', 'romeo',
        'sierra', 'tango', 'uniform', 'victor', 'whiskey', 'xray', 'yankee', 'zulu',
    ];

    /** @var int The seed this generator was created with. */
    public $seed;

    /** @var array{int, int, int, int} xoshiro128** state, four 32-bit words. */
    private $s;

    public function __construct(int $seed = 0)
    {
        if (PHP_INT_SIZE < 8) {
            throw new \RuntimeException('TestData needs 64-bit PHP');
        }
        $this->seed = $seed;
        // splitmix32, seeded from both halves of the 64-bit seed.
        $x = ($seed ^ self::mul32(($seed >> 32) & self::MASK, 0x9e3779b9)) & self::MASK;
        $state = [];
        for ($i = 0; $i < 4; $i++) {
            $x = ($x + 0x9e3779b9) & self::MASK;
            $z = $x;
            $z = self::mul32($z ^ ($z >> 16), 0x85ebca6b);
            $z = self::mul32($z ^ ($z >> 13), 0xc2b2ae35);
            $state[] = ($z ^ ($z >> 16)) & self::MASK;
        }
        $this->s = $state;
    }

    /** `$a * $b mod 2^32` for 32-bit operands, without overflowing PHP's int. */
    private static function mul32(int $a, int $b): int
    {
        return (($a & 0xFFFF) * $b + (((($a >> 16) * $b) & 0xFFFF) << 16)) & self::MASK;
    }

    private static function rotl(int $x, int $k): int
    {
        return (($x << $k) | ($x >> (32 - $k))) & self::MASK;
    }

    /** The next 32 random bits. */
    private function next32(): int
    {
        [$s0, $s1, $s2, $s3] = $this->s;
        $result = (self::rotl(($s1 * 5) & self::MASK, 7) * 9) & self::MASK;
        $t = ($s1 << 9) & self::MASK;
        $s2 ^= $s0;
        $s3 ^= $s1;
        $s1 ^= $s2;
        $s0 ^= $s3;
        $s2 ^= $t;
        $s3 = self::rotl($s3, 11);
        $this->s = [$s0, $s1, $s2, $s3];
        return $result;
    }

    /** An unbiased integer in [0, $n) for 1 <= $n <= 2^62. */
    private function below(int $n): int
    {
        if ($n <= 1 << 32) {
            $limit = intdiv(1 << 32, $n) * $n;
            do {
                $r = $this->next32();
            } while ($r >= $limit);
            return $r % $n;
        }
        $limit = intdiv(1 << 62, $n) * $n;
        do {
            $r = (($this->next32() & 0x3FFFFFFF) << 32) | $this->next32();
        } while ($r >= $limit);
        return $r % $n;
    }

    /** A float in `[0, 1)` with 53 random bits. */
    private function float(): float
    {
        return (($this->next32() >> 5) * 67108864.0 + ($this->next32() >> 6)) / 9007199254740992.0;
    }

    /** A generator with a random seed. Read `seed` to reproduce it. */
    public static function randomSeed(): self
    {
        return new self(random_int(0, (1 << 31) - 1));
    }

    /** An integer in `[$min, $max]` (inclusive); the span must be at most 2^62. */
    public function integer(int $min = 0, int $max = 100): int
    {
        if ($max < $min) {
            throw new \InvalidArgumentException("max ($max) < min ($min)");
        }
        $span = $max - $min; // a float if it overflowed
        if (!is_int($span) || $span >= 1 << 62) {
            throw new \OutOfRangeException('max - min must be below 2^62');
        }
        return $min + $this->below($span + 1);
    }

    /** A float in `[$min, $max)`. */
    public function decimal(float $min = 0.0, float $max = 1.0): float
    {
        if ($max < $min) {
            throw new \InvalidArgumentException("max ($max) < min ($min)");
        }
        return $min + $this->float() * ($max - $min);
    }

    /** `true` with the given probability. */
    public function boolean(float $probability = 0.5): bool
    {
        if ($probability < 0 || $probability > 1) {
            throw new \OutOfRangeException("probability must be in [0, 1], got $probability");
        }
        return $this->float() < $probability;
    }

    /** A string of `$length` characters drawn from `$alphabet` (UTF-8 aware). */
    public function string(int $length = 10, string $alphabet = self::ALPHANUMERIC): string
    {
        if ($length < 0) {
            throw new \OutOfRangeException("length must be >= 0, got $length");
        }
        $chars = preg_split('//u', $alphabet, -1, PREG_SPLIT_NO_EMPTY);
        if ($chars === false || $chars === []) {
            throw new \InvalidArgumentException('alphabet must not be empty');
        }
        $out = '';
        for ($i = 0; $i < $length; $i++) {
            $out .= $chars[$this->below(count($chars))];
        }
        return $out;
    }

    /** A short lowercase word. */
    public function word(): string
    {
        return $this->pick(self::WORDS);
    }

    /** A sentence of `$words` words, capitalised and ending with a period. */
    public function sentence(int $words = 6): string
    {
        if ($words < 1) {
            throw new \OutOfRangeException("words must be >= 1, got $words");
        }
        $list = [];
        for ($i = 0; $i < $words; $i++) {
            $list[] = $this->word();
        }
        return ucfirst(implode(' ', $list)) . '.';
    }

    /** A syntactically valid address on the reserved `example.com` domain. */
    public function email(): string
    {
        return $this->word() . '.' . $this->string(5, self::LOWER) . '@example.com';
    }

    /** A version 4 UUID string. */
    public function uuid(): string
    {
        $b = pack('N4', $this->next32(), $this->next32(), $this->next32(), $this->next32());
        $b[6] = chr((ord($b[6]) & 0x0f) | 0x40);
        $b[8] = chr((ord($b[8]) & 0x3f) | 0x80);
        return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($b), 4));
    }

    /** A UTC date in `[$from, $to]` (default 2000-01-01 to 2030-01-01). */
    public function date(?\DateTimeInterface $from = null, ?\DateTimeInterface $to = null): \DateTimeImmutable
    {
        $utc = new \DateTimeZone('UTC');
        $start = ($from ?? new \DateTimeImmutable('2000-01-01', $utc))->getTimestamp();
        $end = ($to ?? new \DateTimeImmutable('2030-01-01', $utc))->getTimestamp();
        if ($end < $start) {
            throw new \InvalidArgumentException('to is before from');
        }
        return (new \DateTimeImmutable('@' . $this->integer($start, $end)))->setTimezone($utc);
    }

    /**
     * A random element of `$options`.
     *
     * @template T
     * @param array<T> $options
     * @return T
     */
    public function pick(array $options)
    {
        if ($options === []) {
            throw new \InvalidArgumentException('options must not be empty');
        }
        $values = array_values($options);
        return $values[$this->below(count($values))];
    }

    /**
     * `$count` values produced by `$generate`.
     *
     * @template T
     * @param callable(self): T $generate
     * @return list<T>
     */
    public function listOf(int $count, callable $generate): array
    {
        if ($count < 0) {
            throw new \OutOfRangeException("count must be >= 0, got $count");
        }
        $out = [];
        for ($i = 0; $i < $count; $i++) {
            $out[] = $generate($this);
        }
        return $out;
    }

    /**
     * A shuffled copy of `$items` (Fisher-Yates; keys are dropped).
     *
     * @template T
     * @param iterable<T> $items
     * @return list<T>
     */
    public function shuffled(iterable $items): array
    {
        $list = is_array($items) ? array_values($items) : iterator_to_array($items, false);
        for ($i = count($list) - 1; $i > 0; $i--) {
            $j = $this->below($i + 1);
            [$list[$i], $list[$j]] = [$list[$j], $list[$i]];
        }
        return $list;
    }
}
