package io.github.lesterkaufungen.suggestedtests.internal;

import io.github.lesterkaufungen.suggestedtests.SystemProbe;
import org.testng.IExecutionListener;

/**
 * Loads the native bridge when a TestNG run starts (Maven Surefire, Gradle,
 * IDEs), so its startup report ({@code SUGGESTEDTESTS_VERBOSE=1} or
 * {@code -Dsuggestedtests.verbose=true}) is printed even in runs that never
 * call a native helper: TestNG's counterpart of {@link LoadBridgeOnSessionStart}.
 *
 * <p>Registered through {@code META-INF/services}, so it needs no setup. It
 * never throws: where the bridge is unavailable, {@link SystemProbe} says why
 * when it is used.
 */
public final class LoadBridgeOnTestNGStart implements IExecutionListener {
  /** Created by TestNG's {@code ServiceLoader}. */
  public LoadBridgeOnTestNGStart() {}

  @Override
  public void onExecutionStart() {
    SystemProbe.isAvailable();
  }

  // Declared for TestNG 6, whose IExecutionListener has no default methods.
  @Override
  public void onExecutionFinish() {}
}
