package io.github.lesterkaufungen.suggestedtests;

import io.github.lesterkaufungen.suggestedtests.internal.NativeBridge;
import java.time.Duration;
import java.util.Optional;

/**
 * Process metrics read through the OS-agnostic Rust bridge (Windows, Linux and macOS) via JNI.
 * The library ships inside the jar.
 *
 * <p>Annotate tests that need it with {@code @RequiresNativeBridge} so they are skipped, with
 * the reason, where it isn't available.
 */
public final class SystemProbe {
  private static final Object LOCK = new Object();
  private static boolean probed;
  private static boolean available;
  private static String unavailable;

  private SystemProbe() {}

  private static void probe() {
    synchronized (LOCK) {
      if (probed) return;
      probed = true;
      try {
        NativeBridge.load();
        int version = NativeBridge.abiVersion();
        if (version != NativeBridge.ABI_VERSION) {
          unavailable =
              "suggestedtests native bridge has ABI v" + version + ", expected v" + NativeBridge.ABI_VERSION + ". Rebuild it.";
          return;
        }
        available = true;
        try {
          // Best-effort and additive (no ABI bump): an older prebuilt that
          // predates this native method must not make the whole bridge
          // look unavailable over it.
          NativeBridge.onLoad();
        } catch (UnsatisfiedLinkError e) {
          // Ignored.
        }
        if (NativeBridge.isTruthy(System.getProperty(NativeBridge.VERBOSE_PROPERTY))) {
          NativeBridge.setVerbose(1);
        }
      } catch (UnsatisfiedLinkError | SecurityException e) {
        unavailable =
            "suggestedtests native bridge is not available for this platform ("
                + e.getMessage()
                + "). Set -D"
                + NativeBridge.PROPERTY
                + " or $"
                + NativeBridge.ENV_VAR
                + " to a library built from native/.";
      }
    }
  }

  /** @return whether the bridge is loaded and has the expected ABI version */
  public static boolean isAvailable() {
    probe();
    return available;
  }

  /** @return empty when available; otherwise why not */
  public static Optional<String> skipReason() {
    probe();
    return available ? Optional.empty() : Optional.of(unavailable);
  }

  private static void ensure(String operation) {
    if (!isAvailable()) throw new NativeBridgeException(operation, NativeBridge.ERR_UNSUPPORTED, unavailable);
  }

  private static void check(String operation, int status) {
    if (status != NativeBridge.OK) throw new NativeBridgeException(operation, status, null);
  }

  /** @return CPU time used by the whole process (all threads) so far */
  public static CpuTime processCpuTime() {
    ensure("processCpuTime");
    long[] out = new long[2];
    check("processCpuTime", NativeBridge.processCpuTime(out));
    return new CpuTime(Duration.ofNanos(out[0]), Duration.ofNanos(out[1]));
  }

  /** @return CPU time used by the calling thread so far, in nanoseconds */
  public static long threadCpuTimeNs() {
    ensure("threadCpuTimeNs");
    long[] out = new long[1];
    check("threadCpuTimeNs", NativeBridge.threadCpuTimeNs(out));
    return out[0];
  }

  /** @return current and peak resident memory of the process */
  public static MemoryUsage memoryUsage() {
    ensure("memoryUsage");
    long[] out = new long[2];
    check("memoryUsage", NativeBridge.memoryUsage(out));
    return new MemoryUsage(out[0], out[1]);
  }

  /** @return the number of logical CPUs available to the process */
  public static int cpuCount() {
    ensure("cpuCount");
    return NativeBridge.cpuCount();
  }

  /**
   * Turns the bridge's startup report on or off.
   *
   * <p>The report is three {@code suggestedtests: ...} lines on stderr describing the platform
   * and environment (OS, arch, libc, container, VM). It is printed at most once per process;
   * turning verbose on prints it now if it hasn't been printed. Verbose controls nothing else. To
   * get it when the bridge loads, start the JVM with {@code SUGGESTEDTESTS_VERBOSE=1} in its
   * environment or with {@code -Dsuggestedtests.verbose=true}.
   *
   * <pre>{@code
   * SystemProbe.setVerbose(true);
   * }</pre>
   *
   * @param verbose whether to print the report
   * @return the previous setting
   */
  public static boolean setVerbose(boolean verbose) {
    ensure("setVerbose");
    return NativeBridge.setVerbose(verbose ? 1 : 0) != 0;
  }

  /** @return whether the bridge's startup report is on (see {@link #setVerbose}) */
  public static boolean verbose() {
    ensure("verbose");
    return NativeBridge.verbose() != 0;
  }
}
