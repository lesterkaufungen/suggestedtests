import io.github.lesterkaufungen.suggestedtests.Benchmark;
import java.time.Duration;
import org.junit.jupiter.api.Test;

class ParserTest {
  @Test
  void parsingStaysFast() {
    Benchmark.of("parse", () -> parser.parse(json)).assertWithin(Duration.ofMillis(5));
  }
}
