package compat;

import static io.github.lesterkaufungen.suggestedtests.Eventually.eventually;
import static org.testng.Assert.assertEquals;
import static org.testng.Assert.assertFalse;
import static org.testng.Assert.assertTrue;
import static org.testng.Assert.expectThrows;

import io.github.lesterkaufungen.suggestedtests.Benchmark;
import io.github.lesterkaufungen.suggestedtests.Leaks;
import io.github.lesterkaufungen.suggestedtests.Memory;
import io.github.lesterkaufungen.suggestedtests.Scenario;
import io.github.lesterkaufungen.suggestedtests.ScenarioStepFailure;
import io.github.lesterkaufungen.suggestedtests.SystemProbe;
import io.github.lesterkaufungen.suggestedtests.TestData;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.testng.annotations.Test;

/** The helpers under TestNG, with no JUnit on the classpath. */
public class HelpersTest {
  @Test
  public void noJUnitOnTheClasspath() {
    for (String name : new String[] {"org.junit.Test", "org.junit.jupiter.api.Test", "org.junit.platform.launcher.Launcher"}) {
      assertFalse(present(name), name + " is on the classpath");
    }
  }

  @Test
  public void performanceBudget() {
    Benchmark.of("sum", () -> {
      long sum = 0;
      for (int i = 0; i < 1000; i++) sum += i;
      if (sum < 0) throw new IllegalStateException();
    }).assertWithin(Duration.ofSeconds(1));
  }

  @Test
  public void overBudgetIsAnAssertionError() {
    AssertionError e = expectThrows(AssertionError.class,
        () -> Benchmark.of("sleepy", () -> Thread.sleep(5)).iterations(3).assertWithin(Duration.ofNanos(1)));
    assertTrue(e.getMessage().contains("sleepy"), e.getMessage());
  }

  @Test
  public void memoryBudget() {
    assertTrue(SystemProbe.isAvailable(), SystemProbe.skipReason().orElse(""));
    Memory.budget().maxPeakGrowth(256 * Memory.MiB).check(() -> new byte[1024].clone());
  }

  @Test
  public void eventuallyRetries() {
    AtomicInteger attempts = new AtomicInteger();
    eventually(() -> assertTrue(attempts.incrementAndGet() >= 3));
  }

  @Test
  public void scenarioNamesTheFailingStep() {
    ScenarioStepFailure e = expectThrows(ScenarioStepFailure.class,
        () -> Scenario.given("a list", () -> new StringBuilder())
            .when("two items are added", b -> b.append("ab"))
            .then("it has three", b -> assertEquals(b.length(), 3)));
    assertTrue(e.getMessage().startsWith("Then: it has three"), e.getMessage());
  }

  @Test
  public void seededData() {
    assertEquals(new TestData(42).email(), new TestData(42).email());
  }

  @Test
  public void threadLeaks() {
    Leaks.assertNoLeakedThreads(() -> {
      Thread t = new Thread(() -> {});
      t.start();
      t.join();
    });
  }

  @Test
  public void aTestNGRunLoadsTheBridge() throws Exception {
    assertEquals(reports(runSuite("1")), 1);
    assertEquals(reports(runSuite(null)), 0);
  }

  /** Runs NoNativeHelpers with TestNG in a fresh JVM; returns its stderr. */
  private static String runSuite(String verbose) throws Exception {
    List<String> command = new ArrayList<>();
    command.add(Paths.get(System.getProperty("java.home"), "bin", "java").toString());
    command.add("-cp");
    command.add(System.getProperty("java.class.path"));
    command.add("org.testng.TestNG");
    command.add("-d");
    command.add(Files.createTempDirectory("testng").toString());
    command.add("-testclass");
    command.add(NoNativeHelpers.class.getName());
    File out = File.createTempFile("testng", ".out"); // not Redirect.DISCARD: Java 9
    File err = File.createTempFile("testng", ".err");
    try {
      ProcessBuilder pb = new ProcessBuilder(command).redirectError(err).redirectOutput(out);
      pb.environment().remove("SUGGESTEDTESTS_VERBOSE");
      if (verbose != null) pb.environment().put("SUGGESTEDTESTS_VERBOSE", verbose);
      assertEquals(pb.start().waitFor(), 0);
      return new String(Files.readAllBytes(err.toPath()), StandardCharsets.UTF_8);
    } finally {
      out.delete();
      err.delete();
    }
  }

  private static int reports(String stderr) {
    return stderr.split("suggestedtests: platform: ", -1).length - 1;
  }

  private static boolean present(String name) {
    try {
      Class.forName(name);
      return true;
    } catch (ClassNotFoundException e) {
      return false;
    }
  }
}
