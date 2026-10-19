package io.github.lesterkaufungen.suggestedtests;

import static org.junit.jupiter.api.Assertions.*;

import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class ConcurrencyTest {
  @Test
  void runsEveryThread() {
    AtomicInteger counter = new AtomicInteger();
    Concurrency.race(8, t -> { for (int i = 0; i < 1000; i++) counter.incrementAndGet(); });
    assertEquals(8000, counter.get());
  }

  @Test
  void exposesARace() {
    int[] unsafe = {0};
    AssertionError e =
        assertThrows(
            AssertionError.class,
            () -> {
              for (int round = 0; round < 50; round++) {
                unsafe[0] = 0;
                // Read, yield, write: a widened window, so lost updates don't
                // depend on how the JIT compiles the loop.
                Concurrency.race(8, t -> {
                  for (int i = 0; i < 1_000; i++) {
                    int v = unsafe[0];
                    Thread.yield();
                    unsafe[0] = v + 1;
                  }
                });
                assertEquals(8_000, unsafe[0]);
              }
            });
    assertNotNull(e);
  }

  @Test
  void reportsAllFailures() {
    AssertionError e = assertThrows(AssertionError.class, () -> Concurrency.race(3, t -> { throw new IllegalStateException("t" + t); }));
    assertTrue(e.getMessage().startsWith("3 of 3 threads failed"), e.getMessage());
    assertEquals(2, e.getSuppressed().length);
  }

  @Test
  void reportsStuckThreadsWithStacks() {
    CountDownLatch never = new CountDownLatch(1);
    AssertionError e = assertThrows(AssertionError.class, () -> Concurrency.race(2, Duration.ofMillis(50), t -> never.await()));
    assertTrue(e.getMessage().startsWith("2 of 2 threads still running after 50.00ms"), e.getMessage());
    assertTrue(e.getMessage().contains("CountDownLatch.await"), e.getMessage());
  }

  @Test
  void validates() {
    assertThrows(IllegalArgumentException.class, () -> Concurrency.race(0, t -> {}));
  }
}
