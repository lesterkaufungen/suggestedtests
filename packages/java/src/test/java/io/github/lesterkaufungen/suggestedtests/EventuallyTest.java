package io.github.lesterkaufungen.suggestedtests;

import static io.github.lesterkaufungen.suggestedtests.Eventually.*;
import static org.junit.jupiter.api.Assertions.*;

import java.io.IOException;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class EventuallyTest {
  @Test
  void returnsOnceConditionHolds() {
    AtomicInteger n = new AtomicInteger();
    int result =
        eventually(Duration.ofSeconds(2), Duration.ofMillis(1), () -> {
          int v = n.incrementAndGet();
          assertTrue(v >= 3);
          return v;
        });
    assertEquals(3, result);
  }

  @Test
  void runnableVariant() {
    AtomicInteger n = new AtomicInteger();
    eventually(() -> assertTrue(n.incrementAndGet() >= 2));
  }

  @Test
  void failsWithLastError() {
    AssertionError e =
        assertThrows(AssertionError.class, () -> eventually(Duration.ofMillis(30), Duration.ofMillis(5), () -> { throw new IOException("boom"); }));
    assertTrue(e.getMessage().matches("(?s)Condition not met within 30.00ms \\(\\d+ attempts\\)\\. Last error:\njava.io.IOException: boom"), e.getMessage());
    assertInstanceOf(IOException.class, e.getCause());
  }

  @Test
  void validates() {
    assertThrows(IllegalArgumentException.class, () -> eventually(Duration.ofMillis(-1), Duration.ZERO, () -> {}));
  }

  private static <T> CompletableFuture<T> failed(Throwable t) {
    CompletableFuture<T> f = new CompletableFuture<>();
    f.completeExceptionally(t);
    return f;
  }

  @Test
  void completesWithin() {
    assertEquals(42, assertCompletesWithin(Duration.ofSeconds(1), CompletableFuture.completedFuture(42)));
    AssertionError e = assertThrows(AssertionError.class, () -> assertCompletesWithin(Duration.ofMillis(10), new CompletableFuture<>()));
    assertEquals("Future did not complete within 10.00ms", e.getMessage());
    assertThrows(IOException.class, () -> assertCompletesWithin(Duration.ofSeconds(1), failed(new IOException("x"))));
  }
}
