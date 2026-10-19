import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.opentest4j.AssertionFailedError;

class CacheTest {
  @Test
  void cacheWarmsUp() throws InterruptedException {
    long deadline = System.nanoTime() + 5_000_000_000L;
    while (true) {
      try {
        assertTrue(cache.isWarm());
        return;
      } catch (AssertionFailedError e) {
        if (System.nanoTime() >= deadline) {
          throw e;
        }
        Thread.sleep(20);
      }
    }
  }
}
