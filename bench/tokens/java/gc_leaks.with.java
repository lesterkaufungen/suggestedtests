import io.github.lesterkaufungen.suggestedtests.Leaks;
import org.junit.jupiter.api.Test;

class EventBusTest {
  @Test
  void unregisteredViewsAreReleased() {
    Leaks.assertGarbageCollected(() -> {
      View view = new View();
      bus.register(view);
      bus.unregister(view);
      return view;
    });
  }
}
