package io.github.lesterkaufungen.suggestedtests;

/** A block of test code that may throw anything, including checked exceptions. */
@FunctionalInterface
public interface ThrowingRunnable {
  /**
   * Runs the block.
   *
   * @throws Throwable whatever the block throws
   */
  void run() throws Throwable;
}
