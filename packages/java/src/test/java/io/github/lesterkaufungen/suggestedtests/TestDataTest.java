package io.github.lesterkaufungen.suggestedtests;

import static org.junit.jupiter.api.Assertions.*;

import java.util.HashSet;
import java.util.Collections;
import java.util.Arrays;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.function.Executable;

class TestDataTest {
  @Test
  void sameSeedSameValues() {
    TestData a = new TestData(42);
    TestData b = new TestData(42);
    assertEquals(Arrays.asList(a.integer(), a.email(), a.uuid()), Arrays.asList(b.integer(), b.email(), b.uuid()));
  }

  @Test
  void sequenceMatchesTheGoPackage() {
    // Reference values from packages/go (NewTestData(42)): same generator, same seeding.
    TestData d = new TestData(42);
    assertEquals(1546998764402558742L, d.nextLong());
    assertEquals(841083, d.integer(0, 1_000_000));
    assertEquals(-3, d.integer(-5, 5));
    assertEquals("ecb8ad47-03b3-40a1-bde6-dc7fe2ec5e64", d.uuid().toString());
  }

  @Test
  void ranges() {
    TestData d = new TestData(1);
    Set<Integer> seen = new TreeSet<>();
    for (int i = 0; i < 300; i++) {
      seen.add(d.integer(3, 5));
      double f = d.decimal(1, 2);
      assertTrue(f >= 1 && f < 2);
    }
    assertEquals(new HashSet<>(Arrays.asList(3, 4, 5)), seen);
    assertEquals(Integer.MAX_VALUE, d.integer(Integer.MAX_VALUE, Integer.MAX_VALUE));
  }

  @Test
  void strings() {
    TestData d = new TestData(2);
    assertEquals(12, d.string(12).length());
    assertTrue(d.string(50, "ab").matches("[ab]{50}"));
    assertTrue(d.string(4, "😀x").codePoints().allMatch(c -> c == 'x' || c == 0x1F600));
    assertTrue(d.sentence(6).matches("[A-Z][a-z]+( [a-z]+){5}\\."));
    assertTrue(d.email().matches("[a-z]+\\.[a-z]{5}@example\\.com"));
    assertEquals(4, d.uuid().version());
    assertEquals(2, d.uuid().variant());
  }

  @Test
  void instantsAndCollections() {
    TestData d = new TestData(3);
    Instant from = Instant.parse("2020-01-01T00:00:00Z");
    Instant to = Instant.parse("2020-02-01T00:00:00Z");
    Instant i = d.instant(from, to);
    assertFalse(i.isBefore(from) || i.isAfter(to));
    assertTrue(Arrays.asList(1, 2, 3).contains(d.pick(Arrays.asList(1, 2, 3))));
    assertEquals(3, d.listOf(3, TestData::word).size());
    assertEquals(new TreeSet<>(Arrays.asList(1, 2, 3, 4)), new TreeSet<>(d.shuffled(Arrays.asList(1, 2, 3, 4))));
  }

  @Test
  void validatesArguments() {
    TestData d = new TestData();
    List<Executable> calls =
        Arrays.asList(
            () -> d.integer(5, 1),
            () -> d.decimal(2, 1),
            () -> d.bool(2),
            () -> d.string(-1),
            () -> d.string(3, ""),
            () -> d.sentence(0),
            () -> d.pick(Collections.emptyList()),
            () -> d.listOf(-1, x -> 1),
            () -> d.instant(Instant.parse("2021-01-01T00:00:00Z"), Instant.parse("2020-01-01T00:00:00Z")));
    for (Executable call : calls) assertThrows(IllegalArgumentException.class, call);
  }

  @Test
  void randomSeedIsReproducible() {
    TestData d = TestData.randomSeed();
    assertEquals(new TestData(d.seed()).integer(), d.integer());
  }
}
