package io.github.lesterkaufungen.suggestedtests;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.function.LongSupplier;

/**
 * Benchmarks and performance budgets.
 *
 * <pre>{@code
 * Benchmark.of("parse", () -> parser.parse(json)).assertWithin(Duration.ofMillis(5));
 *
 * BenchmarkResult r = Benchmark.of("sort", () -> sort(data)).iterations(50).clock(Clock.CPU).run();
 * System.out.println(r); // sort (cpu): n=50 min=1.02ms median=1.10ms ...
 * }</pre>
 */
public final class Benchmark {
  private final String name;
  private final ThrowingRunnable body;
  private int iterations = 20;
  private int warmup = 3;
  private Clock clock = Clock.WALL;
  private Statistic statistic = Statistic.MEDIAN;

  private Benchmark(String name, ThrowingRunnable body) {
    this.name = Objects.requireNonNull(name, "name");
    this.body = Objects.requireNonNull(body, "body");
  }

  /**
   * Starts configuring a benchmark of {@code body}.
   *
   * @param name label used in results and failures
   * @param body the code to measure
   * @return a benchmark with 20 iterations, 3 warm-up runs, the wall clock and the median
   */
  public static Benchmark of(String name, ThrowingRunnable body) {
    return new Benchmark(name, body);
  }

  /**
   * @param iterations timed runs, at least 1
   * @return this
   */
  public Benchmark iterations(int iterations) {
    if (iterations < 1) throw new IllegalArgumentException("iterations must be >= 1, got " + iterations);
    this.iterations = iterations;
    return this;
  }

  /**
   * @param warmup untimed runs before the timed ones, at least 0
   * @return this
   */
  public Benchmark warmup(int warmup) {
    if (warmup < 0) throw new IllegalArgumentException("warmup must be >= 0, got " + warmup);
    this.warmup = warmup;
    return this;
  }

  /**
   * @param clock what to measure
   * @return this
   */
  public Benchmark clock(Clock clock) {
    this.clock = Objects.requireNonNull(clock, "clock");
    return this;
  }

  /**
   * @param statistic the statistic {@link #assertWithin} checks
   * @return this
   */
  public Benchmark statistic(Statistic statistic) {
    this.statistic = Objects.requireNonNull(statistic, "statistic");
    return this;
  }

  private LongSupplier reader() {
    if (clock == Clock.WALL) return System::nanoTime;
    if (!SystemProbe.isAvailable()) {
      throw new IllegalStateException("Clock.CPU needs the native bridge: " + SystemProbe.skipReason().orElse(""));
    }
    return SystemProbe::threadCpuTimeNs;
  }

  /**
   * Runs the body {@code warmup} times untimed, then {@code iterations} times timed.
   *
   * @return the timing statistics
   */
  public BenchmarkResult run() {
    LongSupplier now = reader();
    for (int i = 0; i < warmup; i++) Sneaky.run(body);
    List<Duration> samples = new ArrayList<>(iterations);
    for (int i = 0; i < iterations; i++) {
      long start = now.getAsLong();
      Sneaky.run(body);
      samples.add(Duration.ofNanos(now.getAsLong() - start));
    }
    return new BenchmarkResult(name, samples, clock);
  }

  /**
   * Runs the benchmark and fails if the chosen statistic exceeds {@code budget}.
   *
   * @param budget the maximum allowed value
   * @return the result, for logging
   */
  public BenchmarkResult assertWithin(Duration budget) {
    if (budget.isNegative()) throw new IllegalArgumentException("budget must be >= 0, got " + budget);
    BenchmarkResult result = run();
    Duration actual = result.get(statistic);
    if (actual.compareTo(budget) > 0) {
      throw new AssertionError(
          "Performance budget exceeded: "
              + statistic.name().toLowerCase(Locale.ROOT)
              + " "
              + Format.duration(actual)
              + " > budget "
              + Format.duration(budget)
              + "\n"
              + result);
    }
    return result;
  }
}
