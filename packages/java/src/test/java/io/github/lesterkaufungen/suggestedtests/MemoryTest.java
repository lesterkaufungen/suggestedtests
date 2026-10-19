package io.github.lesterkaufungen.suggestedtests;

import static org.junit.jupiter.api.Assertions.*;

import io.github.lesterkaufungen.suggestedtests.junit.RequiresNativeBridge;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

class MemoryTest {
  @Test
  void report() {
    MemoryReport r = new MemoryReport(new MemoryUsage(10, 20), new MemoryUsage(15, 30), -50);
    assertEquals(Optional.of(5L), r.rssGrowthBytes());
    assertEquals(Optional.of(10L), r.peakGrowthBytes());
    assertEquals("MemoryReport(heap: -50 B, rss: +5 B, rss peak: +10 B)", r.toString());
    assertFalse(new MemoryReport(null, null, 0).rssGrowthBytes().isPresent());
  }

  @Test
  void heapBudgetFails() {
    List<byte[]> keep = new ArrayList<>();
    AssertionError e =
        assertThrows(
            AssertionError.class,
            () -> Memory.budget().maxHeapGrowth(Memory.MiB).check(() -> { for (int i = 0; i < 64; i++) keep.add(new byte[1 << 20]); }));
    assertTrue(e.getMessage().startsWith("Memory budget exceeded: Java heap grew"), e.getMessage());
    assertEquals(64, keep.size());
  }

  @Test
  @RequiresNativeBridge
  void rssBudgetFails() {
    List<java.nio.ByteBuffer> keep = new ArrayList<>();
    AssertionError e =
        assertThrows(
            AssertionError.class,
            () ->
                Memory.budget()
                    .maxPeakGrowth(0)
                    .check(() -> {
                      java.nio.ByteBuffer b = java.nio.ByteBuffer.allocateDirect(128 << 20);
                      for (int i = 0; i < b.capacity(); i += 4096) b.put(i, (byte) 1);
                      keep.add(b);
                    }));
    assertTrue(e.getMessage().contains("peak RSS grew"), e.getMessage());
  }

  @Test
  void budgetValidates() {
    assertThrows(IllegalStateException.class, () -> Memory.budget().check(() -> {}));
    assertThrows(IllegalArgumentException.class, () -> Memory.budget().maxHeapGrowth(-1));
  }
}
