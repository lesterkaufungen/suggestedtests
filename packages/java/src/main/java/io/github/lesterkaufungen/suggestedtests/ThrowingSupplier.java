package io.github.lesterkaufungen.suggestedtests;

/**
 * Produces a value and may throw anything, including checked exceptions.
 *
 * @param <T> the value type
 */
@FunctionalInterface
public interface ThrowingSupplier<T> {
  /**
   * Produces the value.
   *
   * @return the value
   * @throws Throwable whatever the supplier throws
   */
  T get() throws Throwable;
}
