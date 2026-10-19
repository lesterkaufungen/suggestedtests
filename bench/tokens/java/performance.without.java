import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Arrays;
import org.junit.jupiter.api.Test;

class ParserTest {
  @Test
  void parsingStaysFast() {
    for (int i = 0; i < 3; i++) {
      parser.parse(json);
    }
    long[] samples = new long[20];
    for (int i = 0; i < samples.length; i++) {
      long start = System.nanoTime();
      parser.parse(json);
      samples[i] = System.nanoTime() - start;
    }
    Arrays.sort(samples);
    double medianMs = (samples[9] + samples[10]) / 2e6;
    assertTrue(medianMs <= 5, () -> String.format(
        "parse: median %.2fms > budget 5ms (min %.2fms, max %.2fms)",
        medianMs, samples[0] / 1e6, samples[19] / 1e6));
  }
}
