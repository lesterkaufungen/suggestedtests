package io.github.lesterkaufungen.suggestedtests;

/** Rethrows checked exceptions without declaring them, like test frameworks do. */
final class Sneaky {
  private Sneaky() {}

  static RuntimeException rethrow(Throwable t) {
    return Sneaky.<RuntimeException>doThrow(t);
  }

  @SuppressWarnings("unchecked")
  private static <E extends Throwable> E doThrow(Throwable t) throws E {
    throw (E) t;
  }

  static void run(ThrowingRunnable body) {
    try {
      body.run();
    } catch (Throwable t) {
      throw rethrow(t);
    }
  }

  static <T> T get(ThrowingSupplier<T> body) {
    try {
      return body.get();
    } catch (Throwable t) {
      throw rethrow(t);
    }
  }
}
