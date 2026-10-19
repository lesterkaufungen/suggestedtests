package io.github.lesterkaufungen.suggestedtests;

/** Which statistic of a {@link BenchmarkResult} a budget is checked against. */
public enum Statistic {
  /** Fastest sample. */
  MIN,
  /** Arithmetic mean of all samples. */
  MEAN,
  /** Middle sample. Robust against GC pauses; the default. */
  MEDIAN,
  /** 95th percentile sample. */
  P95,
  /** Slowest sample. */
  MAX
}
