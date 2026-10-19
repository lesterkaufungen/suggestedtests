import static org.junit.jupiter.api.Assertions.assertNull;

import java.lang.ref.WeakReference;
import org.junit.jupiter.api.Test;

class EventBusTest {
  @Test
  void unregisteredViewsAreReleased() throws InterruptedException {
    WeakReference<View> ref = registerAndUnregister();
    long deadline = System.nanoTime() + 5_000_000_000L;
    while (ref.get() != null && System.nanoTime() < deadline) {
      System.gc();
      byte[][] pressure = new byte[16][];
      for (int i = 0; i < pressure.length; i++) {
        pressure[i] = new byte[1 << 20];
      }
      Thread.sleep(20);
    }
    assertNull(ref.get(), "View is still strongly reachable after 5 s of GC");
  }

  // A separate method, so no local variable keeps the view alive.
  private WeakReference<View> registerAndUnregister() {
    View view = new View();
    bus.register(view);
    bus.unregister(view);
    return new WeakReference<>(view);
  }
}
