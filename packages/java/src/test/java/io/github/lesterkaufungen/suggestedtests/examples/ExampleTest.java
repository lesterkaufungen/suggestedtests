package io.github.lesterkaufungen.suggestedtests.examples;

import static io.github.lesterkaufungen.suggestedtests.Eventually.assertCompletesWithin;
import static io.github.lesterkaufungen.suggestedtests.Eventually.eventually;
import static io.github.lesterkaufungen.suggestedtests.SuggestedAssertions.*;
import static org.junit.jupiter.api.Assertions.*;

import io.github.lesterkaufungen.suggestedtests.BenchmarkResult;
import java.util.Arrays;
import io.github.lesterkaufungen.suggestedtests.Benchmark;
import io.github.lesterkaufungen.suggestedtests.Clock;
import io.github.lesterkaufungen.suggestedtests.Concurrency;
import io.github.lesterkaufungen.suggestedtests.Leaks;
import io.github.lesterkaufungen.suggestedtests.Memory;
import io.github.lesterkaufungen.suggestedtests.Scenario;
import io.github.lesterkaufungen.suggestedtests.Spy;
import io.github.lesterkaufungen.suggestedtests.TestData;
import io.github.lesterkaufungen.suggestedtests.junit.MemoryBudget;
import io.github.lesterkaufungen.suggestedtests.junit.RequiresNativeBridge;
import io.github.lesterkaufungen.suggestedtests.junit.SuggestedTests;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.LongAdder;
import java.util.function.Consumer;
import org.junit.jupiter.api.Test;

/** A tour of suggestedtests. Run it with: ./mvnw test -Dtest=ExampleTest */
@SuggestedTests
class ExampleTest {
  static final class Cart {
    private final List<Integer> items = new ArrayList<>();

    Cart add(int price) {
      items.add(price);
      return this;
    }

    int total() {
      return items.stream().mapToInt(Integer::intValue).sum();
    }
  }

  @Test
  void givenWhenThen() {
    Scenario.given("an empty cart", Cart::new)
        .when("two items are added", cart -> cart.add(10).add(20))
        .then("the total is 30", cart -> assertEquals(30, cart.total()));
  }

  @Test
  void seededDataIsUnique(TestData data) {
    assertUnique(data.listOf(100, TestData::uuid));
  }

  @Test
  void sortingStaysFast() {
    List<Integer> numbers = new TestData(1).listOf(10_000, d -> d.integer(0, 1_000_000));
    Benchmark.of("sort", () -> new ArrayList<>(numbers).sort(null)).assertWithin(Duration.ofMillis(50));
  }

  @Test
  @RequiresNativeBridge
  void cpuTimeIgnoresWaiting() {
    BenchmarkResult result = Benchmark.of("sleep", () -> Thread.sleep(2)).iterations(3).clock(Clock.CPU).run();
    assertTrue(result.median().compareTo(Duration.ofMillis(1)) < 0, result.toString());
  }

  @Test
  @MemoryBudget(maxHeapGrowthBytes = 256 * Memory.MiB)
  void buildingRowsStaysUnderBudget() {
    assertEquals(1000, new TestData().listOf(1000, TestData::email).size());
  }

  @Test
  void callbackIsCalled() {
    Spy<Consumer<String>> onItem = Spy.consumer();
    Arrays.asList("apple", "pear").forEach(onItem.get());
    assertCalledTimes(onItem, 2);
    assertCalledWith(onItem, "pear");
  }

  @Test
  void counterIsThreadSafe() {
    LongAdder counter = new LongAdder();
    Concurrency.race(8, thread -> { for (int i = 0; i < 1000; i++) counter.increment(); });
    assertEquals(8000, counter.sum());
  }

  @Test
  void listenersAreReleased() {
    List<Object> listeners = new ArrayList<>();
    Leaks.assertGarbageCollected(() -> {
      Object listener = new Object();
      listeners.add(listener);
      listeners.remove(listener);
      return listener;
    });
  }

  @Test
  void backgroundWorkFinishes() {
    AtomicBoolean done = new AtomicBoolean();
    Leaks.assertNoLeakedThreads(() -> new Thread(() -> done.set(true)).start());
    eventually(() -> assertTrue(done.get()));
    assertEquals("ok", assertCompletesWithin(Duration.ofSeconds(1), CompletableFuture.supplyAsync(() -> "ok")));
  }
}
