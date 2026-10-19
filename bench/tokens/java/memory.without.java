import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import org.junit.jupiter.api.Test;

class ImporterTest {
  // Linux only: the JVM has no portable way to read the process's peak RSS.
  private static long peakRssKiB() throws IOException {
    for (String line : Files.readAllLines(Paths.get("/proc/self/status"))) {
      if (line.startsWith("VmHWM:")) {
        return Long.parseLong(line.replaceAll("\\D+", ""));
      }
    }
    throw new IllegalStateException("no VmHWM in /proc/self/status");
  }

  @Test
  void importStaysSmall() throws IOException {
    long before = peakRssKiB();
    importer.run(bigFile);
    long growthKiB = peakRssKiB() - before;
    assertTrue(growthKiB <= 50 * 1024,
        () -> String.format("peak RSS grew by %.1f MiB > 50 MiB", growthKiB / 1024.0));
  }
}
