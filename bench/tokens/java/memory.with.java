import io.github.lesterkaufungen.suggestedtests.Memory;
import io.github.lesterkaufungen.suggestedtests.junit.MemoryBudget;
import io.github.lesterkaufungen.suggestedtests.junit.RequiresNativeBridge;
import org.junit.jupiter.api.Test;

class ImporterTest {
  @Test
  @RequiresNativeBridge
  @MemoryBudget(maxPeakGrowthBytes = 50 * Memory.MiB)
  void importStaysSmall() {
    importer.run(bigFile);
  }
}
