package io.github.lesterkaufungen.suggestedtests;

import static org.junit.jupiter.api.Assertions.*;

import java.lang.ref.WeakReference;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import org.junit.jupiter.api.Test;

class LeaksTest {
  private static final List<Object> REGISTRY = new ArrayList<>();

  @Test
  void collectableObjectPasses() {
    Leaks.assertGarbageCollected(() -> {
      Object o = new Object();
      REGISTRY.add(o);
      REGISTRY.remove(o);
      return o;
    });
  }

  @Test
  void retainedObjectFails() {
    Object kept = new StringBuilder("kept");
    REGISTRY.add(kept);
    try {
      AssertionError e = assertThrows(AssertionError.class, () -> Leaks.assertGarbageCollected(new WeakReference<>(kept), Duration.ofMillis(100)));
      assertTrue(e.getMessage().startsWith("Object of type java.lang.StringBuilder was not garbage collected"), e.getMessage());
    } finally {
      REGISTRY.clear();
    }
  }

  @Test
  void finishedThreadsPass() {
    Leaks.assertNoLeakedThreads(() -> {
      Thread t = new Thread(() -> {});
      t.start();
    });
  }

  @Test
  void leakedThreadsFail() throws InterruptedException {
    CountDownLatch stop = new CountDownLatch(1);
    Thread[] started = new Thread[1];
    try {
      AssertionError e =
          assertThrows(
              AssertionError.class,
              () -> Leaks.assertNoLeakedThreads(Duration.ofMillis(50), () -> {
                started[0] = new Thread(() -> { try { stop.await(); } catch (InterruptedException ignored) { } }, "leaky");
                started[0].start();
              }));
      assertTrue(e.getMessage().contains("\"leaky\""), e.getMessage());
    } finally {
      stop.countDown();
      if (started[0] != null) started[0].join();
    }
  }
}
