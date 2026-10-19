package io.github.lesterkaufungen.suggestedtests;

import java.util.List;

/**
 * Thrown when a {@link Scenario} step fails. An {@link AssertionError}, so test runners
 * report a failure; the original error is the cause.
 */
public final class ScenarioStepFailure extends AssertionError {
  private static final long serialVersionUID = 1L;

  private final String step;

  ScenarioStepFailure(String step, List<String> passed, Throwable cause) {
    super(message(step, passed, cause), cause);
    this.step = step;
    setStackTrace(cause.getStackTrace());
  }

  private static String message(String step, List<String> passed, Throwable cause) {
    StringBuilder s = new StringBuilder(step).append('\n').append(cause);
    if (!passed.isEmpty()) {
      s.append("\nPassed steps:");
      for (String p : passed) s.append("\n  ✓ ").append(p);
    }
    return s.toString();
  }

  /** @return the failed step, e.g. {@code Then: the total is 30} */
  public String step() {
    return step;
  }
}
