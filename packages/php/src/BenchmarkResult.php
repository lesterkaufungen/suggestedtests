<?php

declare(strict_types=1);

namespace SuggestedTests;

/** Timing statistics collected by {@see Benchmark::run()}. All durations are in milliseconds. */
final class BenchmarkResult
{
    /** @var string Label of the benchmark. */
    public $name;
    /** @var list<float> Measured durations in run order (warm-up runs excluded). */
    public $samples;
    /** @var string What the samples measure: a {@see Clock} constant. */
    public $clock;
    /** @var list<float> */
    private $sorted;

    /** @param list<float> $samples */
    public function __construct(string $name, array $samples, string $clock = Clock::Wall)
    {
        if ($samples === []) {
            throw new \InvalidArgumentException('samples must not be empty');
        }
        $this->name = $name;
        $this->samples = array_values($samples);
        $this->clock = Clock::check($clock);
        $sorted = $this->samples;
        sort($sorted);
        $this->sorted = $sorted;
    }

    /** Fastest sample. */
    public function min(): float
    {
        return (float) $this->sorted[0];
    }

    /** Slowest sample. */
    public function max(): float
    {
        return (float) $this->sorted[count($this->sorted) - 1];
    }

    /** Arithmetic mean. */
    public function mean(): float
    {
        return array_sum($this->samples) / count($this->samples);
    }

    /** Median (50th percentile). */
    public function median(): float
    {
        return $this->percentile(50);
    }

    /** 95th percentile. */
    public function p95(): float
    {
        return $this->percentile(95);
    }

    /** Population standard deviation. */
    public function stdDev(): float
    {
        $m = $this->mean();
        $sum = 0.0;
        foreach ($this->samples as $s) {
            $sum += ($s - $m) ** 2;
        }
        return sqrt($sum / count($this->samples));
    }

    /** The `$p`th percentile (0-100) using nearest-rank. */
    public function percentile(float $p): float
    {
        if ($p < 0 || $p > 100) {
            throw new \OutOfRangeException("p must be in [0, 100], got $p");
        }
        $n = count($this->sorted);
        $rank = min(max((int) ceil($p / 100 * $n), 1), $n);
        return (float) $this->sorted[$rank - 1];
    }

    /** The value of `$statistic`, a {@see Statistic} constant. */
    public function get(string $statistic): float
    {
        switch (Statistic::check($statistic)) {
            case Statistic::Min:
                return $this->min();
            case Statistic::Mean:
                return $this->mean();
            case Statistic::P95:
                return $this->p95();
            case Statistic::Max:
                return $this->max();
            default:
                return $this->median();
        }
    }

    public function __toString(): string
    {
        return sprintf(
            '%s%s: n=%d min=%s median=%s mean=%s p95=%s max=%s ±%s',
            $this->name,
            $this->clock === Clock::Cpu ? ' (cpu)' : '',
            count($this->samples),
            Format::ms($this->min()),
            Format::ms($this->median()),
            Format::ms($this->mean()),
            Format::ms($this->p95()),
            Format::ms($this->max()),
            Format::ms($this->stdDev())
        );
    }
}
