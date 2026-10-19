package io.github.lesterkaufungen.suggestedtests;

import java.time.Duration;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

/** Polling and timing assertions that replace fixed sleeps. */
public final class Eventually {
  private static final Duration DEFAULT_TIMEOUT = Duration.ofSeconds(5);
  private static final Duration DEFAULT_INTERVAL = Duration.ofMillis(20);

  private Eventually() {}

  /**
   * Re-runs {@code body} every 20 ms until it returns without throwing, for up to 5 seconds.
   *
   * <pre>{@code
   * eventually(() -> assertTrue(cache.isWarm()));
   * }</pre>
   *
   * @param body the condition, usually containing assertions
   */
  public static void eventually(ThrowingRunnable body) {
    eventually(DEFAULT_TIMEOUT, DEFAULT_INTERVAL, body);
  }

  /**
   * Re-runs {@code body} until it returns without throwing, then returns its result. Fails
   * with the last error after 5 seconds.
   *
   * @param <T> the result type
   * @param body the condition
   * @return the body's first successful result
   */
  public static <T> T eventually(ThrowingSupplier<T> body) {
    return eventually(DEFAULT_TIMEOUT, DEFAULT_INTERVAL, body);
  }

  /**
   * Like {@link #eventually(ThrowingRunnable)} with explicit timing.
   *
   * @param timeout give up after this long
   * @param interval wait this long between attempts
   * @param body the condition
   */
  public static void eventually(Duration timeout, Duration interval, ThrowingRunnable body) {
    eventually(
        timeout,
        interval,
        () -> {
          body.run();
          return null;
        });
  }

  /**
   * Like {@link #eventually(ThrowingSupplier)} with explicit timing.
   *
   * @param <T> the result type
   * @param timeout give up after this long
   * @param interval wait this long between attempts
   * @param body the condition
   * @return the body's first successful result
   */
  public static <T> T eventually(Duration timeout, Duration interval, ThrowingSupplier<T> body) {
    if (timeout.isNegative()) throw new IllegalArgumentException("timeout must be >= 0, got " + timeout);
    if (interval.isNegative()) throw new IllegalArgumentException("interval must be >= 0, got " + interval);
    long start = System.nanoTime();
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        return body.get();
      } catch (Throwable error) {
        if (error instanceof InterruptedException || error instanceof VirtualMachineError) {
          throw Sneaky.rethrow(error);
        }
        if (System.nanoTime() - start >= timeout.toNanos()) {
          throw new AssertionError(
              "Condition not met within "
                  + Format.duration(timeout)
                  + " ("
                  + attempts
                  + " attempts). Last error:\n"
                  + error,
              error);
        }
      }
      try {
        Thread.sleep(interval.toMillis(), (int) (interval.toNanos() % 1_000_000));
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw Sneaky.rethrow(e);
      }
    }
  }

  /**
   * Waits for {@code future} and fails unless it completes successfully within {@code limit}.
   * A failed future rethrows its cause.
   *
   * <pre>{@code
   * User user = assertCompletesWithin(Duration.ofSeconds(1), client.fetchUser(42));
   * }</pre>
   *
   * @param <T> the result type
   * @param limit maximum wait
   * @param future the asynchronous result
   * @return its value
   */
  public static <T> T assertCompletesWithin(Duration limit, CompletionStage<T> future) {
    if (limit.isNegative()) throw new IllegalArgumentException("limit must be >= 0, got " + limit);
    try {
      return future.toCompletableFuture().get(limit.toNanos(), TimeUnit.NANOSECONDS);
    } catch (TimeoutException e) {
      throw new AssertionError("Future did not complete within " + Format.duration(limit), e);
    } catch (ExecutionException e) {
      throw Sneaky.rethrow(e.getCause());
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw Sneaky.rethrow(e);
    }
  }
}
