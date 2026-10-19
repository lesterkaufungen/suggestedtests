import static io.github.lesterkaufungen.suggestedtests.Eventually.eventually;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class CacheTest {
  @Test
  void cacheWarmsUp() {
    eventually(() -> assertTrue(cache.isWarm()));
  }
}
