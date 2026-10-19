package io.github.lesterkaufungen.suggestedtests;

import java.lang.ref.WeakReference;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

/** Checks that objects and threads don't outlive the code that created them. */
public final class Leaks {
  private Leaks() {}

  /**
   * Fails unless the referent of {@code ref} is garbage collected within 5 seconds, which means
   * nothing references it anymore.
   *
   * @param ref a weak reference to the object
   */
  public static void assertGarbageCollected(WeakReference<?> ref) {
    assertGarbageCollected(ref, Duration.ofSeconds(5));
  }

  /**
   * Like {@link #assertGarbageCollected(WeakReference)} with an explicit timeout.
   *
   * @param ref a weak reference to the object
   * @param timeout how long to keep collecting
   */
  public static void assertGarbageCollected(WeakReference<?> ref, Duration timeout) {
    long deadline = System.nanoTime() + timeout.toNanos();
    String type = null;
    while (true) {
      Object referent = ref.get();
      if (referent == null) return;
      type = referent.getClass().getName();
      referent = null;
      if (System.nanoTime() >= deadline) break;
      System.gc();
      // Allocation pressure makes collectors that ignore System.gc() run too.
      byte[][] pressure = new byte[16][];
      for (int i = 0; i < pressure.length; i++) pressure[i] = new byte[1 << 20];
      try {
        Thread.sleep(10);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw Sneaky.rethrow(e);
      }
    }
    throw new AssertionError(
        "Object of type " + type + " was not garbage collected within " + Format.duration(timeout)
            + ": something still references it");
  }

  /**
   * Runs {@code create}, then fails unless the object it returns becomes garbage. Use it to
   * check that registries, caches and listeners let go:
   *
   * <pre>{@code
   * Leaks.assertGarbageCollected(() -> {
   *   View view = new View();
   *   bus.register(view);
   *   bus.unregister(view);
   *   return view;
   * });
   * }</pre>
   *
   * @param create creates (and uses) the object
   */
  public static void assertGarbageCollected(ThrowingSupplier<?> create) {
    assertGarbageCollected(new WeakReference<>(Sneaky.get(create)));
  }

  /**
   * Runs {@code body} and fails if threads it started are still alive 1 second later.
   *
   * @param body the code under test
   */
  public static void assertNoLeakedThreads(ThrowingRunnable body) {
    assertNoLeakedThreads(Duration.ofSeconds(1), body);
  }

  /**
   * Like {@link #assertNoLeakedThreads(ThrowingRunnable)} with an explicit grace period.
   *
   * @param grace how long threads may take to finish after {@code body}
   * @param body the code under test
   */
  public static void assertNoLeakedThreads(Duration grace, ThrowingRunnable body) {
    Set<Thread> before = Thread.getAllStackTraces().keySet();
    Sneaky.run(body);
    long deadline = System.nanoTime() + grace.toNanos();
    while (true) {
      List<Thread> leaked = new ArrayList<>();
      for (Thread t : Thread.getAllStackTraces().keySet()) {
        if (!before.contains(t) && t.isAlive()) leaked.add(t);
      }
      if (leaked.isEmpty()) return;
      long left = deadline - System.nanoTime();
      if (left <= 0) {
        StringBuilder s = new StringBuilder(leaked.size() + " thread(s) still running after the body:");
        for (Thread t : leaked) {
          s.append("\n  \"").append(t.getName()).append("\" ").append(t.getState()).append(t.isDaemon() ? " (daemon)" : "");
        }
        throw new AssertionError(s.toString());
      }
      try {
        leaked.get(0).join(Math.max(1, Math.min(left / 1_000_000, 50)));
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw Sneaky.rethrow(e);
      }
    }
  }
}
