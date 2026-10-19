package io.github.lesterkaufungen.suggestedtests;

import java.time.Duration;
import java.util.Locale;

/** Human readable sizes and durations, as used in failure messages. */
public final class Format {
  private Format() {}

  /**
   * Formats a byte count, e.g. {@code 12.5 MiB}.
   *
   * @param bytes the size; may be negative
   * @return the formatted size
   */
  public static String bytes(long bytes) {
    String[] units = {"B", "KiB", "MiB", "GiB", "TiB"};
    double value = Math.abs((double) bytes);
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) return bytes + " B";
    return String.format(Locale.ROOT, "%s%.1f %s", bytes < 0 ? "-" : "", value, units[unit]);
  }

  /**
   * Formats a duration as {@code 850µs}, {@code 1.25ms} or {@code 2.00s}.
   *
   * @param duration the duration
   * @return the formatted duration
   */
  public static String duration(Duration duration) {
    double us = duration.toNanos() / 1e3;
    if (Math.abs(us) < 1000) return Math.round(us) + "µs";
    if (Math.abs(us) < 1_000_000) return String.format(Locale.ROOT, "%.2fms", us / 1e3);
    return String.format(Locale.ROOT, "%.2fs", us / 1e6);
  }
}
