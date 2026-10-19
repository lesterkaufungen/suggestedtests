package io.github.lesterkaufungen.suggestedtests;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/** Timing statistics collected by {@link Benchmark#run()}. */
public final class BenchmarkResult {
  private final String name;
  private final Clock clock;
  private final List<Duration> samples;
  private final List<Duration> sorted;

  /**
   * Creates a result.
   *
   * @param name label of the benchmark
   * @param samples measured durations in run order (warm-up excluded); must not be empty
   * @param clock what the samples measure
   */
  public BenchmarkResult(String name, List<Duration> samples, Clock clock) {
    this.name = Objects.requireNonNull(name, "name");
    this.clock = Objects.requireNonNull(clock, "clock");
    if (samples.isEmpty()) throw new IllegalArgumentException("samples must not be empty");
    this.samples = Collections.unmodifiableList(new ArrayList<>(samples));
    List<Duration> s = new ArrayList<>(samples);
    Collections.sort(s);
    this.sorted = Collections.unmodifiableList(s);
  }

  /** @return label of the benchmark */
  public String name() {
    return name;
  }

  /** @return what the samples measure */
  public Clock clock() {
    return clock;
  }

  /** @return measured durations in run order */
  public List<Duration> samples() {
    return samples;
  }

  /** @return fastest sample */
  public Duration min() {
    return sorted.get(0);
  }

  /** @return slowest sample */
  public Duration max() {
    return sorted.get(sorted.size() - 1);
  }

  /** @return arithmetic mean */
  public Duration mean() {
    long total = 0;
    for (Duration d : samples) total += d.toNanos();
    return Duration.ofNanos(Math.round((double) total / samples.size()));
  }

  /** @return median (50th percentile) */
  public Duration median() {
    return percentile(50);
  }

  /** @return 95th percentile */
  public Duration p95() {
    return percentile(95);
  }

  /** @return population standard deviation */
  public Duration stdDev() {
    double mean = mean().toNanos();
    double sum = 0;
    for (Duration d : samples) sum += Math.pow(d.toNanos() - mean, 2);
    return Duration.ofNanos(Math.round(Math.sqrt(sum / samples.size())));
  }

  /**
   * The {@code p}th percentile using nearest-rank.
   *
   * @param p 0 to 100
   * @return the sample at that rank
   */
  public Duration percentile(double p) {
    if (!(p >= 0 && p <= 100)) throw new IllegalArgumentException("p must be in [0, 100], got " + p);
    int rank = (int) Math.min(Math.max(Math.ceil(p / 100 * sorted.size()), 1), sorted.size());
    return sorted.get(rank - 1);
  }

  /**
   * @param statistic which statistic
   * @return its value
   */
  public Duration get(Statistic statistic) {
    switch (statistic) {
      case MIN:
        return min();
      case MEAN:
        return mean();
      case MEDIAN:
        return median();
      case P95:
        return p95();
      case MAX:
        return max();
      default:
        throw new IllegalArgumentException(String.valueOf(statistic));
    }
  }

  @Override
  public String toString() {
    return name
        + (clock == Clock.CPU ? " (cpu)" : "")
        + ": n="
        + samples.size()
        + " min="
        + Format.duration(min())
        + " median="
        + Format.duration(median())
        + " mean="
        + Format.duration(mean())
        + " p95="
        + Format.duration(p95())
        + " max="
        + Format.duration(max())
        + " ±"
        + Format.duration(stdDev());
  }
}
