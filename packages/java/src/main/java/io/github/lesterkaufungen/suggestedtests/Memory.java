package io.github.lesterkaufungen.suggestedtests;

import io.github.lesterkaufungen.suggestedtests.internal.NativeBridge;
import java.util.Optional;

/**
 * Memory budgets. Process RSS (native bridge) covers everything the process holds, including
 * direct buffers and native libraries; the Java heap figure covers objects.
 *
 * <pre>{@code
 * Memory.budget().maxPeakGrowth(50 * Memory.MiB).check(() -> repository.loadAll());
 * }</pre>
 */
public final class Memory {
  /** Bytes in a kibibyte. */
  public static final long KiB = 1024;
  /** Bytes in a mebibyte. */
  public static final long MiB = 1024 * KiB;
  /** Bytes in a gibibyte. */
  public static final long GiB = 1024 * MiB;

  private Memory() {}

  // Runtime rather than java.lang.management, which Android doesn't have.
  private static long usedHeap() {
    Runtime runtime = Runtime.getRuntime();
    for (int i = 0; i < 3; i++) System.gc();
    return runtime.totalMemory() - runtime.freeMemory();
  }

  /**
   * Runs {@code body} and reports how memory changed.
   *
   * @param body the code to measure
   * @return the report
   */
  public static MemoryReport measure(ThrowingRunnable body) {
    Measurement m = start();
    Sneaky.run(body);
    return m.finish();
  }

  /**
   * Takes the "before" samples of a measurement that spans more than one block, e.g. test
   * callbacks. Prefer {@link #measure}.
   *
   * @return the started measurement
   */
  public static Measurement start() {
    return new Measurement();
  }

  /** A measurement started by {@link #start()}. */
  public static final class Measurement {
    private final MemoryUsage before;
    private final long heapBefore;

    private Measurement() {
      heapBefore = usedHeap();
      before = SystemProbe.isAvailable() ? SystemProbe.memoryUsage() : null;
    }

    /** @return the report from the start until now */
    public MemoryReport finish() {
      MemoryUsage after = before != null ? SystemProbe.memoryUsage() : null;
      return new MemoryReport(before, after, usedHeap() - heapBefore);
    }
  }

  /** @return an empty budget; set at least one limit, then {@link Budget#check} */
  public static Budget budget() {
    return new Budget();
  }

  /** Limits for {@link #budget()}, in bytes. */
  public static final class Budget {
    private long maxRssGrowth = -1;
    private long maxPeakGrowth = -1;
    private long maxHeapGrowth = -1;

    private Budget() {}

    private static long checked(String name, long bytes) {
      if (bytes < 0) throw new IllegalArgumentException(name + " must be >= 0, got " + bytes);
      return bytes;
    }

    /**
     * @param bytes maximum growth of resident memory (needs the native bridge)
     * @return this
     */
    public Budget maxRssGrowth(long bytes) {
      maxRssGrowth = checked("maxRssGrowth", bytes);
      return this;
    }

    /**
     * @param bytes maximum rise of the process' peak resident memory (needs the native bridge)
     * @return this
     */
    public Budget maxPeakGrowth(long bytes) {
      maxPeakGrowth = checked("maxPeakGrowth", bytes);
      return this;
    }

    /**
     * @param bytes maximum growth of the used Java heap
     * @return this
     */
    public Budget maxHeapGrowth(long bytes) {
      maxHeapGrowth = checked("maxHeapGrowth", bytes);
      return this;
    }

    /**
     * Runs {@code body} and fails if memory grew more than the budget.
     *
     * @param body the code to measure
     * @return the report, for logging
     */
    public MemoryReport check(ThrowingRunnable body) {
      validate();
      return verify(measure(body));
    }

    /**
     * Throws if no limit is set, or an RSS limit is set but the native bridge is missing.
     * {@link #check} does this before running its body.
     */
    public void validate() {
      if (maxRssGrowth < 0 && maxPeakGrowth < 0 && maxHeapGrowth < 0) {
        throw new IllegalStateException("Set maxRssGrowth, maxPeakGrowth and/or maxHeapGrowth.");
      }
      if (needsNativeBridge() && !SystemProbe.isAvailable()) {
        throw new NativeBridgeException(
            "memoryUsage", NativeBridge.ERR_UNSUPPORTED, SystemProbe.skipReason().orElse(null));
      }
    }

    /** @return whether an RSS limit is set */
    public boolean needsNativeBridge() {
      return maxRssGrowth >= 0 || maxPeakGrowth >= 0;
    }

    /**
     * Fails if {@code report} exceeds this budget.
     *
     * @param report a finished measurement
     * @return the report
     */
    public MemoryReport verify(MemoryReport report) {
      check(maxHeapGrowth, Optional.of(report.heapGrowthBytes()), "Java heap grew", report);
      check(maxRssGrowth, report.rssGrowthBytes(), "RSS grew", report);
      check(maxPeakGrowth, report.peakGrowthBytes(), "peak RSS grew", report);
      return report;
    }

    private static void check(long limit, Optional<Long> actual, String what, MemoryReport report) {
      if (limit >= 0 && actual.isPresent() && actual.get() > limit) {
        throw new AssertionError(
            "Memory budget exceeded: "
                + what
                + " "
                + Format.bytes(actual.get())
                + " > budget "
                + Format.bytes(limit)
                + "\n"
                + report);
      }
    }
  }
}
