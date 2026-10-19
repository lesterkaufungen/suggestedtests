package io.github.lesterkaufungen.suggestedtests.internal;

import io.github.lesterkaufungen.suggestedtests.SystemProbe;
import org.junit.platform.launcher.LauncherSession;
import org.junit.platform.launcher.LauncherSessionListener;

/**
 * Loads the native bridge when a JUnit Platform session opens (Maven Surefire,
 * Gradle, IDEs), so its startup report ({@code SUGGESTEDTESTS_VERBOSE=1} or
 * {@code -Dsuggestedtests.verbose=true}) is printed even in runs that never
 * call a native helper.
 *
 * <p>Registered through {@code META-INF/services}, so it needs no setup. It
 * never throws: where the bridge is unavailable, {@link SystemProbe} says why
 * when it is used.
 */
public final class LoadBridgeOnSessionStart implements LauncherSessionListener {
  /** Created by the JUnit Platform's {@code ServiceLoader}. */
  public LoadBridgeOnSessionStart() {}

  @Override
  public void launcherSessionOpened(LauncherSession session) {
    SystemProbe.isAvailable();
  }
}
