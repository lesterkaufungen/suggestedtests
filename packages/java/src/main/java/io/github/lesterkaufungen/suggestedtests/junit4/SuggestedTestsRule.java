package io.github.lesterkaufungen.suggestedtests.junit4;

import io.github.lesterkaufungen.suggestedtests.Memory;
import io.github.lesterkaufungen.suggestedtests.MemoryReport;
import io.github.lesterkaufungen.suggestedtests.SystemProbe;
import io.github.lesterkaufungen.suggestedtests.TestData;
import io.github.lesterkaufungen.suggestedtests.junit.MemoryBudget;
import io.github.lesterkaufungen.suggestedtests.junit.RequiresNativeBridge;
import io.github.lesterkaufungen.suggestedtests.junit.Seed;
import java.lang.annotation.Annotation;
import java.util.concurrent.ThreadLocalRandom;
import org.junit.AssumptionViolatedException;
import org.junit.rules.TestRule;
import org.junit.runner.Description;
import org.junit.runners.model.Statement;

/**
 * JUnit 4 support, for projects (including Android's local and instrumented
 * tests) that don't run JUnit 5. It honours the same annotations as the JUnit 5
 * extension: {@link RequiresNativeBridge}, {@link Seed} and {@link MemoryBudget}.
 *
 * <pre>{@code
 * public class SignupTest {
 *   @Rule public final SuggestedTestsRule st = new SuggestedTestsRule();
 *
 *   @Test
 *   public void acceptsAnyValidEmail() {
 *     assertTrue(signup.accepts(st.testData().email()));
 *   }
 *
 *   @Test
 *   @RequiresNativeBridge
 *   @MemoryBudget(maxPeakGrowthBytes = 64 * Memory.MiB)
 *   public void importStaysSmall() { importer.run(bigFile); }
 * }
 * }</pre>
 *
 * <p>When a test that used {@link #testData()} fails, its seed is attached to
 * the failure. The system property {@code suggestedtests.seed} (or
 * {@code $SUGGESTEDTESTS_SEED}) fixes the seed of every test.
 */
public final class SuggestedTestsRule implements TestRule {
  private Description description;
  private TestData testData;

  /**
   * Creates the rule; declare it as a public {@code @Rule} field. Loads the
   * native bridge, so its startup report prints in plain JUnit 4 runs too.
   */
  public SuggestedTestsRule() {
    SystemProbe.isAvailable();
  }

  /**
   * Seeded test data for the current test; the same instance for the whole test.
   *
   * @return the generator
   */
  public TestData testData() {
    if (testData == null) testData = new TestData(seed());
    return testData;
  }

  /** Skips the current test, with the reason, where the native bridge is unavailable. */
  public void requireNativeBridge() {
    if (!SystemProbe.isAvailable()) {
      throw new AssumptionViolatedException(SystemProbe.skipReason().orElse("native bridge unavailable"));
    }
  }

  private long seed() {
    String property = System.getProperty("suggestedtests.seed");
    if (property == null || property.isEmpty()) property = System.getenv("SUGGESTEDTESTS_SEED");
    if (property != null && !property.isEmpty()) return Long.parseLong(property.trim());
    Seed seed = description == null ? null : find(description, Seed.class);
    return seed != null ? seed.value() : ThreadLocalRandom.current().nextInt(Integer.MAX_VALUE);
  }

  private static <A extends Annotation> A find(Description description, Class<A> type) {
    A a = description.getAnnotation(type);
    if (a == null && description.getTestClass() != null) a = description.getTestClass().getAnnotation(type);
    return a;
  }

  @Override
  public Statement apply(Statement base, Description description) {
    return new Statement() {
      @Override
      public void evaluate() throws Throwable {
        SuggestedTestsRule.this.description = description;
        testData = null;
        if (find(description, RequiresNativeBridge.class) != null) requireNativeBridge();
        MemoryBudget annotation = find(description, MemoryBudget.class);
        Memory.Budget budget = annotation == null ? null : toBudget(annotation);
        if (budget != null) {
          if (budget.needsNativeBridge()) requireNativeBridge();
          budget.validate();
        }
        Memory.Measurement measurement = budget == null ? null : Memory.start();
        try {
          base.evaluate();
        } catch (AssumptionViolatedException e) {
          throw e;
        } catch (Throwable t) {
          if (testData != null) {
            t.addSuppressed(
                new SeedReport(
                    "TestData seed was " + testData.seed() + "; reproduce with -Dsuggestedtests.seed=" + testData.seed()));
          }
          throw t;
        }
        if (measurement != null) {
          MemoryReport report = measurement.finish();
          budget.verify(report);
        }
      }
    };
  }

  private static Memory.Budget toBudget(MemoryBudget annotation) {
    Memory.Budget b = Memory.budget();
    if (annotation.maxRssGrowthBytes() >= 0) b.maxRssGrowth(annotation.maxRssGrowthBytes());
    if (annotation.maxPeakGrowthBytes() >= 0) b.maxPeakGrowth(annotation.maxPeakGrowthBytes());
    if (annotation.maxHeapGrowthBytes() >= 0) b.maxHeapGrowth(annotation.maxHeapGrowthBytes());
    return b;
  }

  /** Carries the seed of a failed test in its stack trace output. Not thrown on its own. */
  static final class SeedReport extends Exception {
    private static final long serialVersionUID = 1L;

    SeedReport(String message) {
      super(message, null, false, false);
    }
  }
}
