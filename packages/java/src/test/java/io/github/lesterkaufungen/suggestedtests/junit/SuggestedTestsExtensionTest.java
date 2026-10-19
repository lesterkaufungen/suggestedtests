package io.github.lesterkaufungen.suggestedtests.junit;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClass;
import static org.junit.platform.testkit.engine.EventConditions.event;
import static org.junit.platform.testkit.engine.EventConditions.finishedWithFailure;
import static org.junit.platform.testkit.engine.EventConditions.test;
import static org.junit.platform.testkit.engine.TestExecutionResultConditions.message;

import io.github.lesterkaufungen.suggestedtests.Memory;
import io.github.lesterkaufungen.suggestedtests.TestData;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.platform.testkit.engine.EngineTestKit;
import org.junit.platform.testkit.engine.Events;

class SuggestedTestsExtensionTest {
  @SuggestedTests
  static class Injected {
    static long seen;

    @Test
    @Seed(1234)
    void fixedSeed(TestData data) {
      seen = data.seed();
    }

    @Test
    @Seed(99)
    void fails(TestData data) {
      fail("boom");
    }

    @Test
    void sameInstanceWithinATest(TestData a, TestData b) {
      assertSame(a, b);
    }
  }

  static class Budgets {
    static final List<byte[]> KEEP = new ArrayList<>();

    @Test
    @MemoryBudget(maxHeapGrowthBytes = 1024)
    void overBudget() {
      for (int i = 0; i < 32; i++) KEEP.add(new byte[1 << 20]);
    }

    @Test
    @MemoryBudget(maxHeapGrowthBytes = 512 * Memory.MiB)
    void withinBudget() {}
  }

  private static Events run(Class<?> c) {
    return EngineTestKit.engine("junit-jupiter").selectors(selectClass(c)).execute().testEvents();
  }

  @Test
  void injectsSeededTestDataAndReportsSeedOnFailure() {
    Events events = run(Injected.class);
    events.assertStatistics(s -> s.succeeded(2).failed(1));
    assertEquals(1234, Injected.seen);
    Throwable failure =
        events.failed().stream().findFirst().get().getRequiredPayload(org.junit.platform.engine.TestExecutionResult.class).getThrowable().get();
    assertTrue(
        Arrays.stream(failure.getSuppressed()).anyMatch(s -> s.getMessage().equals("TestData seed was 99; reproduce with -Dsuggestedtests.seed=99")),
        Arrays.toString(failure.getSuppressed()));
  }

  @Test
  void memoryBudgetFailsTheTest() {
    Events events = run(Budgets.class);
    events.assertStatistics(s -> s.succeeded(1).failed(1));
    events.assertThatEvents().haveExactly(1, event(test("overBudget"), finishedWithFailure(message(m -> m.startsWith("Memory budget exceeded: Java heap grew")))));
    Budgets.KEEP.clear();
  }

  @RequiresNativeBridge
  static class NeedsBridge {
    @Test
    void runs() {}
  }

  @Test
  void requiresNativeBridgeRunsWhereAvailable() {
    run(NeedsBridge.class).assertStatistics(s -> s.succeeded(io.github.lesterkaufungen.suggestedtests.SystemProbe.isAvailable() ? 1 : 0));
  }
}
