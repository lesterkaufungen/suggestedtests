package io.github.lesterkaufungen.suggestedtests;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;

/** Stress helpers for thread-safety tests. */
public final class Concurrency {
  private Concurrency() {}

  /** A body run by each thread of {@link #race}. */
  @FunctionalInterface
  public interface ThreadBody {
    /**
     * @param thread index of the thread, from 0
     * @throws Throwable to fail the race
     */
    void run(int thread) throws Throwable;
  }

  /**
   * Starts {@code threads} threads, releases them at the same instant, and runs {@code body}
   * in each, which maximises contention. Fails if any thread throws (the first error is the
   * cause, the others are suppressed) or if they don't finish within 10 seconds, printing the
   * stuck threads' stacks, which usually point at a deadlock.
   *
   * <pre>{@code
   * Counter counter = new Counter();
   * Concurrency.race(8, t -> { for (int i = 0; i < 1000; i++) counter.increment(); });
   * assertEquals(8000, counter.get());
   * }</pre>
   *
   * @param threads number of threads, at least 1
   * @param body run by each thread with its index
   */
  public static void race(int threads, ThreadBody body) {
    race(threads, Duration.ofSeconds(10), body);
  }

  /**
   * Like {@link #race(int, ThreadBody)} with an explicit timeout.
   *
   * @param threads number of threads, at least 1
   * @param timeout how long all threads may take together
   * @param body run by each thread with its index
   */
  public static void race(int threads, Duration timeout, ThreadBody body) {
    if (threads < 1) throw new IllegalArgumentException("threads must be >= 1, got " + threads);
    if (timeout.isNegative()) throw new IllegalArgumentException("timeout must be >= 0, got " + timeout);
    CountDownLatch ready = new CountDownLatch(threads);
    CountDownLatch go = new CountDownLatch(1);
    Queue<Throwable> errors = new ConcurrentLinkedQueue<>();
    List<Thread> workers = new ArrayList<>(threads);
    for (int i = 0; i < threads; i++) {
      int index = i;
      Thread t =
          new Thread(
              () -> {
                ready.countDown();
                try {
                  go.await();
                  body.run(index);
                } catch (Throwable e) {
                  errors.add(e);
                }
              },
              "suggestedtests-race-" + i);
      t.setDaemon(true);
      workers.add(t);
      t.start();
    }
    try {
      ready.await();
      go.countDown();
      long deadline = System.nanoTime() + timeout.toNanos();
      for (Thread t : workers) {
        long left = deadline - System.nanoTime();
        if (left > 0) t.join(Math.max(1, left / 1_000_000));
      }
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw Sneaky.rethrow(e);
    }
    List<Thread> stuck = new ArrayList<>();
    for (Thread t : workers) if (t.isAlive()) stuck.add(t);
    if (!stuck.isEmpty()) {
      StringBuilder s =
          new StringBuilder(stuck.size() + " of " + threads + " threads still running after " + Format.duration(timeout) + ":");
      for (Thread t : stuck) {
        s.append("\n\"").append(t.getName()).append("\" ").append(t.getState());
        for (StackTraceElement e : t.getStackTrace()) s.append("\n    at ").append(e);
        t.interrupt();
      }
      throw new AssertionError(s.toString());
    }
    if (!errors.isEmpty()) {
      Throwable first = errors.poll();
      AssertionError error = new AssertionError((errors.size() + 1) + " of " + threads + " threads failed: " + first, first);
      errors.forEach(error::addSuppressed);
      throw error;
    }
  }
}
