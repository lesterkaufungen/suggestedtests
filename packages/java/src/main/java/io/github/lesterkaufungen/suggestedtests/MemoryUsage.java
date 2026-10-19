package io.github.lesterkaufungen.suggestedtests;

/** Resident memory (RSS / working set) of the process, in bytes. */
public final class MemoryUsage {
  private final long currentRssBytes;
  private final long peakRssBytes;

  /**
   * Creates a sample.
   *
   * @param currentRssBytes memory currently resident in RAM
   * @param peakRssBytes highest resident memory since the process started
   */
  public MemoryUsage(long currentRssBytes, long peakRssBytes) {
    this.currentRssBytes = currentRssBytes;
    this.peakRssBytes = peakRssBytes;
  }

  /** @return memory currently resident in RAM */
  public long currentRssBytes() {
    return currentRssBytes;
  }

  /** @return highest resident memory since the process started */
  public long peakRssBytes() {
    return peakRssBytes;
  }

  @Override
  public boolean equals(Object o) {
    return o instanceof MemoryUsage
        && ((MemoryUsage) o).currentRssBytes == currentRssBytes
        && ((MemoryUsage) o).peakRssBytes == peakRssBytes;
  }

  @Override
  public int hashCode() {
    return Long.hashCode(currentRssBytes) * 31 + Long.hashCode(peakRssBytes);
  }

  @Override
  public String toString() {
    return "MemoryUsage(current: " + Format.bytes(currentRssBytes) + ", peak: " + Format.bytes(peakRssBytes) + ")";
  }
}
