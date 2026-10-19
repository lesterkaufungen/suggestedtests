package io.github.lesterkaufungen.suggestedtests.junit4;

import static org.junit.jupiter.api.Assertions.*;

import io.github.lesterkaufungen.suggestedtests.Memory;
import io.github.lesterkaufungen.suggestedtests.SystemProbe;
import io.github.lesterkaufungen.suggestedtests.junit.MemoryBudget;
import io.github.lesterkaufungen.suggestedtests.junit.RequiresNativeBridge;
import io.github.lesterkaufungen.suggestedtests.junit.Seed;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.Rule;
import org.junit.runner.JUnitCore;
import org.junit.runner.Result;
import org.junit.runner.notification.Failure;

/** Runs JUnit 4 classes with JUnitCore from a JUnit 5 test. */
class SuggestedTestsRuleTest {
  public static class Fixture {
    static long seen;
    static final List<byte[]> KEEP = new ArrayList<>();

    @Rule public final SuggestedTestsRule st = new SuggestedTestsRule();

    @org.junit.Test
    @Seed(1234)
    public void fixedSeed() {
      seen = st.testData().seed();
      org.junit.Assert.assertSame(st.testData(), st.testData());
    }

    @org.junit.Test
    @Seed(99)
    public void fails() {
      st.testData().word();
      org.junit.Assert.fail("boom");
    }

    @org.junit.Test
    @MemoryBudget(maxHeapGrowthBytes = 1024)
    public void overBudget() {
      for (int i = 0; i < 32; i++) KEEP.add(new byte[1 << 20]);
    }

    @org.junit.Test
    @RequiresNativeBridge
    public void needsBridge() {
      org.junit.Assert.assertTrue(SystemProbe.memoryUsage().currentRssBytes() > Memory.MiB);
    }
  }

  @org.junit.jupiter.api.Test
  void ruleHonoursAnnotationsAndReportsSeed() {
    Result result = JUnitCore.runClasses(Fixture.class);
    Fixture.KEEP.clear();
    assertEquals(4, result.getRunCount());
    assertEquals(1234, Fixture.seen);
    assertEquals(SystemProbe.isAvailable() ? 0 : 1, result.getAssumptionFailureCount());
    assertEquals(2, result.getFailureCount(), result.getFailures().toString());
    for (Failure f : result.getFailures()) {
      String name = f.getDescription().getMethodName();
      if (name.equals("fails")) {
        assertTrue(
            Arrays.stream(f.getException().getSuppressed())
                .anyMatch(s -> s.getMessage().equals("TestData seed was 99; reproduce with -Dsuggestedtests.seed=99")),
            Arrays.toString(f.getException().getSuppressed()));
      } else {
        assertEquals("overBudget", name);
        assertTrue(f.getMessage().startsWith("Memory budget exceeded: Java heap grew"), f.getMessage());
      }
    }
  }
}
