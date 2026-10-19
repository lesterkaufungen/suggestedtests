import io.github.lesterkaufungen.suggestedtests.Benchmark;
import io.github.lesterkaufungen.suggestedtests.Clock;
import io.github.lesterkaufungen.suggestedtests.Memory;
import io.github.lesterkaufungen.suggestedtests.Scenario;
import io.github.lesterkaufungen.suggestedtests.Spy;
import io.github.lesterkaufungen.suggestedtests.SuggestedAssertions;
import io.github.lesterkaufungen.suggestedtests.SystemProbe;
import io.github.lesterkaufungen.suggestedtests.TestData;
import io.github.lesterkaufungen.suggestedtests.internal.NativeBridge;
import java.time.Duration;
import java.util.function.Function;

/**
 * Runs the Java library on Android's runtime (ART) without an app: tool/android_smoke.sh dexes it
 * with D8 and starts it with app_process. Prints OK/FAIL lines; exits non-zero on failure.
 */
public final class AndroidSmoke {
  private static int failures;

  private static void check(String name, Runnable body) {
    try {
      body.run();
      System.out.println("OK   " + name);
    } catch (Throwable t) {
      failures++;
      System.out.println("FAIL " + name + ": " + t);
    }
  }

  public static void main(String[] args) {
    check("runtime is Android", () -> {
      if (!NativeBridge.isAndroid()) throw new AssertionError(System.getProperty("java.vm.name"));
    });
    check("native bridge via System.loadLibrary", () -> {
      if (!SystemProbe.isAvailable()) throw new AssertionError(SystemProbe.skipReason().orElse(""));
      System.out.println("     " + SystemProbe.memoryUsage() + " " + SystemProbe.processCpuTime() + " cpus=" + SystemProbe.cpuCount());
      if (SystemProbe.threadCpuTimeNs() <= 0) throw new AssertionError("thread cpu");
    });
    check("benchmark (wall and cpu)", () -> {
      Benchmark.of("sum", () -> { long x = 0; for (int i = 0; i < 10000; i++) x += i; }).assertWithin(Duration.ofSeconds(1));
      System.out.println("     " + Benchmark.of("cpu", () -> {}).iterations(5).clock(Clock.CPU).run());
    });
    check("memory budget", () -> Memory.budget().maxPeakGrowth(512 * Memory.MiB).maxHeapGrowth(256 * Memory.MiB).check(() -> new byte[1 << 20].hashCode()));
    check("test data", () -> {
      TestData d = new TestData(42);
      if (!new TestData(42).uuid().equals(d.uuid())) throw new AssertionError("not deterministic");
      SuggestedAssertions.assertUnique(d.listOf(50, TestData::uuid));
    });
    check("scenario", () -> Scenario.given("a value", () -> 20).then("is 20", v -> { if (v != 20) throw new AssertionError(); }));
    check("spy (java.lang.reflect.Proxy on ART)", () -> {
      Spy<Function<String, Integer>> parse = Spy.function(Integer::parseInt);
      parse.get().apply("7");
      SuggestedAssertions.assertCalledWith(parse, "7");
    });
    System.out.println(failures == 0 ? "ALL PASSED" : failures + " FAILED");
    System.exit(failures == 0 ? 0 : 1);
  }
}
