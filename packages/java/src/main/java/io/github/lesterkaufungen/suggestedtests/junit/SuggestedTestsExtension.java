package io.github.lesterkaufungen.suggestedtests.junit;

import io.github.lesterkaufungen.suggestedtests.Memory;
import io.github.lesterkaufungen.suggestedtests.MemoryReport;
import io.github.lesterkaufungen.suggestedtests.SystemProbe;
import io.github.lesterkaufungen.suggestedtests.TestData;
import java.lang.reflect.AnnotatedElement;
import java.util.Optional;
import java.util.concurrent.ThreadLocalRandom;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.extension.AfterTestExecutionCallback;
import org.junit.jupiter.api.extension.BeforeTestExecutionCallback;
import org.junit.jupiter.api.extension.ConditionEvaluationResult;
import org.junit.jupiter.api.extension.ExecutionCondition;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.junit.jupiter.api.extension.ParameterContext;
import org.junit.jupiter.api.extension.ParameterResolver;
import org.junit.jupiter.api.extension.TestExecutionExceptionHandler;

/**
 * The JUnit 5 extension behind {@link SuggestedTests}, {@link Seed}, {@link
 * RequiresNativeBridge} and {@link MemoryBudget}. Usually registered through those
 * annotations.
 */
public final class SuggestedTestsExtension
    implements ParameterResolver,
        TestExecutionExceptionHandler,
        ExecutionCondition,
        BeforeTestExecutionCallback,
        AfterTestExecutionCallback {

  /** System property that fixes the {@link TestData} seed of every test. */
  public static final String SEED_PROPERTY = "suggestedtests.seed";

  private static final ExtensionContext.Namespace NS =
      ExtensionContext.Namespace.create(SuggestedTestsExtension.class);

  /** Creates the extension; JUnit does this. Loads the native bridge. */
  public SuggestedTestsExtension() {
    SystemProbe.isAvailable();
  }

  private static <A extends java.lang.annotation.Annotation> Optional<A> find(
      ExtensionContext context, Class<A> type) {
    for (Optional<? extends AnnotatedElement> e = context.getElement(); e.isPresent(); ) {
      A a = e.get().getAnnotation(type);
      if (a != null) return Optional.of(a);
      context = context.getParent().orElse(null);
      if (context == null) break;
      e = context.getElement();
    }
    return Optional.empty();
  }

  @Override
  public ConditionEvaluationResult evaluateExecutionCondition(ExtensionContext context) {
    if (!find(context, RequiresNativeBridge.class).isPresent()) {
      return ConditionEvaluationResult.enabled("no @RequiresNativeBridge");
    }
    return SystemProbe.skipReason()
        .map(ConditionEvaluationResult::disabled)
        .orElseGet(() -> ConditionEvaluationResult.enabled("native bridge available"));
  }

  @Override
  public boolean supportsParameter(ParameterContext parameter, ExtensionContext context) {
    return parameter.getParameter().getType() == TestData.class;
  }

  @Override
  public Object resolveParameter(ParameterContext parameter, ExtensionContext context) {
    // get/put rather than getOrComputeIfAbsent, which JUnit 6 deprecates; parameters of one
    // test are resolved on one thread.
    ExtensionContext.Store store = context.getStore(NS);
    TestData data = store.get("testData", TestData.class);
    if (data == null) {
      data = new TestData(seed(context));
      store.put("testData", data);
    }
    return data;
  }

  private static long seed(ExtensionContext context) {
    String property = System.getProperty(SEED_PROPERTY);
    if (property == null || property.isEmpty()) property = System.getenv("SUGGESTEDTESTS_SEED");
    if (property != null && !property.isEmpty()) return Long.parseLong(property.trim());
    return find(context, Seed.class)
        .map(Seed::value)
        .orElseGet(() -> (long) ThreadLocalRandom.current().nextInt(Integer.MAX_VALUE));
  }

  @Override
  public void handleTestExecutionException(ExtensionContext context, Throwable throwable) throws Throwable {
    TestData data = context.getStore(NS).get("testData", TestData.class);
    if (data != null) {
      throwable.addSuppressed(
          new SeedReport(
              "TestData seed was " + data.seed() + "; reproduce with -D" + SEED_PROPERTY + "=" + data.seed()));
    }
    throw throwable;
  }

  /** Carries the seed of a failed test in its stack trace output. Not thrown on its own. */
  static final class SeedReport extends Exception {
    private static final long serialVersionUID = 1L;

    SeedReport(String message) {
      super(message, null, false, false);
    }
  }

  @Override
  public void beforeTestExecution(ExtensionContext context) {
    Optional<MemoryBudget> annotation = find(context, MemoryBudget.class);
    if (!annotation.isPresent()) return;
    Memory.Budget budget = toBudget(annotation.get());
    if (budget.needsNativeBridge()) {
      Assumptions.assumeTrue(SystemProbe.isAvailable(), () -> SystemProbe.skipReason().orElse(""));
    }
    budget.validate();
    context.getStore(NS).put("budget", budget);
    context.getStore(NS).put("measurement", Memory.start());
  }

  @Override
  public void afterTestExecution(ExtensionContext context) {
    Memory.Budget budget = context.getStore(NS).remove("budget", Memory.Budget.class);
    Memory.Measurement measurement = context.getStore(NS).remove("measurement", Memory.Measurement.class);
    if (budget == null || measurement == null || context.getExecutionException().isPresent()) return;
    MemoryReport report = measurement.finish();
    context.publishReportEntry("suggestedtests.memory", report.toString());
    budget.verify(report);
  }

  private static Memory.Budget toBudget(MemoryBudget annotation) {
    Memory.Budget b = Memory.budget();
    if (annotation.maxRssGrowthBytes() >= 0) b.maxRssGrowth(annotation.maxRssGrowthBytes());
    if (annotation.maxPeakGrowthBytes() >= 0) b.maxPeakGrowth(annotation.maxPeakGrowthBytes());
    if (annotation.maxHeapGrowthBytes() >= 0) b.maxHeapGrowth(annotation.maxHeapGrowthBytes());
    return b;
  }
}
