package io.github.lesterkaufungen.suggestedtests;

/**
 * Consumes a value and may throw anything, including checked exceptions.
 *
 * @param <T> the value type
 */
@FunctionalInterface
public interface ThrowingConsumer<T> {
  /**
   * Consumes the value.
   *
   * @param value the value
   * @throws Throwable whatever the consumer throws
   */
  void accept(T value) throws Throwable;
}
