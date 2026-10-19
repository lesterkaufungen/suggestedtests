package io.github.lesterkaufungen.suggestedtests;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Collections;
import java.util.Arrays;
import io.github.lesterkaufungen.suggestedtests.junit.RequiresNativeBridge;
import java.io.IOException;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class BenchmarkTest {
  private static List<Duration> ns(long... values) {
    return java.util.Arrays.stream(values).mapToObj(Duration::ofNanos).collect(java.util.stream.Collectors.toList());
  }

  @Test
  void statistics() {
    BenchmarkResult r = new BenchmarkResult("r", ns(5, 1, 3, 2, 4), Clock.WALL);
    assertEquals(ns(1, 5, 3, 3, 5), Arrays.asList(r.min(), r.max(), r.mean(), r.median(), r.p95()));
    assertEquals(Duration.ofNanos(3), r.get(Statistic.MEDIAN));
    assertEquals(Duration.ofNanos(1), r.percentile(0));
    assertEquals(Duration.ofNanos(1), r.stdDev());
    assertEquals(ns(5, 1, 3, 2, 4), r.samples());
  }

  @Test
  void resultValidates() {
    assertThrows(IllegalArgumentException.class, () -> new BenchmarkResult("r", Collections.emptyList(), Clock.WALL));
    BenchmarkResult r = new BenchmarkResult("r", ns(1), Clock.WALL);
    assertThrows(IllegalArgumentException.class, () -> r.percentile(101));
  }

  @Test
  void toStringFormatsUnits() {
    String s = new BenchmarkResult("x", ns(500_000, 2_500_000, 3_000_000_000L), Clock.CPU).toString();
    assertTrue(s.startsWith("x (cpu): n=3 min=500µs median=2.50ms mean=1.00s"), s);
  }

  @Test
  void runCountsCalls() {
    AtomicInteger calls = new AtomicInteger();
    BenchmarkResult r = Benchmark.of("b", calls::incrementAndGet).iterations(5).warmup(2).run();
    assertEquals(7, calls.get());
    assertEquals(5, r.samples().size());
  }

  @Test
  void validatesEagerly() {
    assertThrows(IllegalArgumentException.class, () -> Benchmark.of("b", () -> {}).iterations(0));
    assertThrows(IllegalArgumentException.class, () -> Benchmark.of("b", () -> {}).warmup(-1));
    assertThrows(IllegalArgumentException.class, () -> Benchmark.of("b", () -> {}).assertWithin(Duration.ofMillis(-1)));
    assertThrows(NullPointerException.class, () -> Benchmark.of("b", null));
  }

  @Test
  void checkedExceptionsPropagate() {
    assertThrows(IOException.class, () -> Benchmark.of("b", () -> { throw new IOException("x"); }).run());
  }

  @Test
  void assertWithinFails() {
    AssertionError e =
        assertThrows(
            AssertionError.class,
            () -> Benchmark.of("repeat", () -> String.join("", Collections.nCopies(100_000, "x"))).iterations(2).statistic(Statistic.MAX).assertWithin(Duration.ZERO));
    assertTrue(e.getMessage().matches("(?s)Performance budget exceeded: max .* > budget 0µs\nrepeat: n=2.*"), e.getMessage());
  }

  @Test
  void assertWithinPasses() {
    assertEquals("ok", Benchmark.of("ok", () -> {}).assertWithin(Duration.ofSeconds(1)).name());
  }

  @Test
  @RequiresNativeBridge
  void cpuClockIgnoresSleep() {
    BenchmarkResult r = Benchmark.of("sleep", () -> Thread.sleep(10)).iterations(3).warmup(0).clock(Clock.CPU).run();
    assertEquals(Clock.CPU, r.clock());
    assertTrue(r.median().compareTo(Duration.ofMillis(5)) < 0, r.toString());
  }
}
