package io.github.lesterkaufungen.suggestedtests;

/** What a benchmark measures. */
public enum Clock {
  /** Elapsed time ({@link System#nanoTime()}). Includes waiting, GC and other processes. */
  WALL,
  /**
   * CPU time of the calling thread, via the native bridge. Ignores waiting, other threads
   * (including the JIT and GC threads) and other processes, so it is far less noisy on busy CI
   * machines.
   */
  CPU
}
