package io.github.lesterkaufungen.suggestedtests;

import java.util.Optional;

/** How memory changed while running a body with {@link Memory#measure}. */
public final class MemoryReport {
  private final MemoryUsage before;
  private final MemoryUsage after;
  private final long heapGrowthBytes;

  /**
   * Creates a report.
   *
   * @param before native RSS sample before the body, or null without the bridge
   * @param after native RSS sample after the body, or null without the bridge
   * @param heapGrowthBytes change of the JVM's used heap (after a GC request)
   */
  public MemoryReport(MemoryUsage before, MemoryUsage after, long heapGrowthBytes) {
    this.before = before;
    this.after = after;
    this.heapGrowthBytes = heapGrowthBytes;
  }

  /** @return the RSS sample before the body, if the bridge is available */
  public Optional<MemoryUsage> before() {
    return Optional.ofNullable(before);
  }

  /** @return the RSS sample after the body, if the bridge is available */
  public Optional<MemoryUsage> after() {
    return Optional.ofNullable(after);
  }

  /** @return change in resident memory (can be negative), if the bridge is available */
  public Optional<Long> rssGrowthBytes() {
    return before == null || after == null
        ? Optional.empty()
        : Optional.of(after.currentRssBytes() - before.currentRssBytes());
  }

  /** @return how far the body pushed the process' peak RSS up, if the bridge is available */
  public Optional<Long> peakGrowthBytes() {
    return before == null || after == null
        ? Optional.empty()
        : Optional.of(after.peakRssBytes() - before.peakRssBytes());
  }

  /**
   * Change of the used Java heap. The JVM is asked to collect garbage before both samples,
   * but {@link System#gc()} is only a hint, so treat small values as noise.
   *
   * @return the change in bytes
   */
  public long heapGrowthBytes() {
    return heapGrowthBytes;
  }

  private static String signed(Optional<Long> bytes) {
    return bytes.map(b -> (b >= 0 ? "+" : "") + Format.bytes(b)).orElse("n/a");
  }

  @Override
  public String toString() {
    return "MemoryReport(heap: "
        + signed(Optional.of(heapGrowthBytes))
        + ", rss: "
        + signed(rssGrowthBytes())
        + ", rss peak: "
        + signed(peakGrowthBytes())
        + ")";
  }
}
