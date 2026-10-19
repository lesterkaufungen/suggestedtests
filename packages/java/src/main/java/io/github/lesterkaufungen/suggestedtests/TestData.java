package io.github.lesterkaufungen.suggestedtests;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import java.util.UUID;
import java.util.function.Function;

/**
 * Seeded random test data. A self-contained xoshiro256** generator (seeded with splitmix64, the
 * same as the Go package's), so a seed produces the same values on every JVM and on Android,
 * where {@code SplittableRandom} is missing before API 24. A failing test can be reproduced
 * exactly.
 *
 * <pre>{@code
 * TestData data = new TestData(42);
 * User user = new User(data.word(), data.email(), data.integer(18, 90));
 * }</pre>
 *
 * <p>With {@code @SuggestedTests}, declare a {@code TestData} parameter to get one seeded per
 * test; its seed is reported when the test fails.
 */
public final class TestData {
  /** The default alphabet of {@link #string(int)}. */
  public static final String ALPHANUMERIC =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

  private static final String LOWER = "abcdefghijklmnopqrstuvwxyz";
  private static final List<String> WORDS =
      Arrays.asList(
          "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india",
          "juliet", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo",
          "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu");

  private final long seed;
  private final long[] s = new long[4];

  /** Creates a generator with seed 0. */
  public TestData() {
    this(0);
  }

  /** @param seed the seed this generator is created with */
  public TestData(long seed) {
    this.seed = seed;
    long x = seed;
    for (int i = 0; i < 4; i++) { // splitmix64
      x += 0x9e3779b97f4a7c15L;
      long z = x;
      z = (z ^ (z >>> 30)) * 0xbf58476d1ce4e5b9L;
      z = (z ^ (z >>> 27)) * 0x94d049bb133111ebL;
      s[i] = z ^ (z >>> 31);
    }
  }

  /** @return a generator with a random seed; read {@link #seed()} to reproduce it */
  public static TestData randomSeed() {
    return new TestData(ThreadLocalRandom.current().nextInt(Integer.MAX_VALUE));
  }

  /** @return the next 64 random bits */
  public long nextLong() {
    long result = Long.rotateLeft(s[1] * 5, 7) * 9;
    long t = s[1] << 17;
    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];
    s[2] ^= t;
    s[3] = Long.rotateLeft(s[3], 45);
    return result;
  }

  /** An unbiased value in [0, n) for unsigned n > 0. */
  private long below(long n) {
    long threshold = Long.remainderUnsigned(-n, n);
    while (true) {
      long r = nextLong();
      if (Long.compareUnsigned(r, threshold) >= 0) return Long.remainderUnsigned(r, n);
    }
  }

  /** A double in [0, 1) with 53 random bits. */
  private double nextDouble() {
    return (nextLong() >>> 11) * 0x1.0p-53;
  }

  /** @return the seed this generator was created with */
  public long seed() {
    return seed;
  }

  /** @return an integer in [0, 100] */
  public int integer() {
    return integer(0, 100);
  }

  /**
   * @param min lowest value
   * @param max highest value (inclusive)
   * @return an integer in [min, max]
   */
  public int integer(int min, int max) {
    if (max < min) throw new IllegalArgumentException("max (" + max + ") < min (" + min + ")");
    return (int) (min + below((long) max - min + 1));
  }

  /**
   * @param min lowest value
   * @param max upper bound (exclusive, unless equal to min)
   * @return a double in [min, max)
   */
  public double decimal(double min, double max) {
    if (max < min) throw new IllegalArgumentException("max (" + max + ") < min (" + min + ")");
    return min + nextDouble() * (max - min);
  }

  /**
   * @param probability chance of {@code true}, in [0, 1]
   * @return {@code true} with that probability
   */
  public boolean bool(double probability) {
    if (!(probability >= 0 && probability <= 1)) {
      throw new IllegalArgumentException("probability must be in [0, 1], got " + probability);
    }
    return nextDouble() < probability;
  }

  /**
   * @param length number of characters
   * @return a string of alphanumeric characters
   */
  public String string(int length) {
    return string(length, ALPHANUMERIC);
  }

  /**
   * @param length number of code points
   * @param alphabet the characters to draw from
   * @return a string of {@code length} code points drawn from {@code alphabet}
   */
  public String string(int length, String alphabet) {
    if (length < 0) throw new IllegalArgumentException("length must be >= 0, got " + length);
    int[] chars = alphabet.codePoints().toArray();
    if (chars.length == 0) throw new IllegalArgumentException("alphabet must not be empty");
    StringBuilder out = new StringBuilder(length);
    for (int i = 0; i < length; i++) out.appendCodePoint(chars[(int) below(chars.length)]);
    return out.toString();
  }

  /** @return a short lowercase word */
  public String word() {
    return pick(WORDS);
  }

  /**
   * @param words number of words, at least 1
   * @return a capitalised sentence ending with a period
   */
  public String sentence(int words) {
    if (words < 1) throw new IllegalArgumentException("words must be >= 1, got " + words);
    StringBuilder out = new StringBuilder();
    for (int i = 0; i < words; i++) out.append(i == 0 ? "" : " ").append(word());
    return Character.toUpperCase(out.charAt(0)) + out.substring(1) + ".";
  }

  /** @return a syntactically valid address on the reserved {@code example.com} domain */
  public String email() {
    return word() + "." + string(5, LOWER) + "@example.com";
  }

  /** @return a version 4 UUID */
  public UUID uuid() {
    long msb = (nextLong() & ~0xF000L) | 0x4000L;
    long lsb = (nextLong() & 0x3FFFFFFFFFFFFFFFL) | 0x8000000000000000L;
    return new UUID(msb, lsb);
  }

  /** @return an instant in [2000-01-01, 2030-01-01) UTC */
  public Instant instant() {
    return instant(Instant.parse("2000-01-01T00:00:00Z"), Instant.parse("2030-01-01T00:00:00Z"));
  }

  /**
   * @param from earliest instant
   * @param to latest instant (exclusive, unless equal to from)
   * @return an instant in [from, to), at millisecond precision
   */
  public Instant instant(Instant from, Instant to) {
    if (to.isBefore(from)) throw new IllegalArgumentException("to is before from");
    long a = from.toEpochMilli();
    long b = to.toEpochMilli();
    return Instant.ofEpochMilli(a == b ? a : a + below(b - a));
  }

  /**
   * @param <T> the element type
   * @param options the candidates
   * @return a random element
   */
  public <T> T pick(List<T> options) {
    if (options.isEmpty()) throw new IllegalArgumentException("options must not be empty");
    return options.get((int) below(options.size()));
  }

  /**
   * @param <T> the element type
   * @param count number of values
   * @param generate produces each value
   * @return the values
   */
  public <T> List<T> listOf(int count, Function<TestData, T> generate) {
    if (count < 0) throw new IllegalArgumentException("count must be >= 0, got " + count);
    List<T> out = new ArrayList<>(count);
    for (int i = 0; i < count; i++) out.add(generate.apply(this));
    return out;
  }

  /**
   * @param <T> the element type
   * @param items the items
   * @return a shuffled copy (Fisher–Yates)
   */
  public <T> List<T> shuffled(Collection<T> items) {
    List<T> out = new ArrayList<>(items);
    for (int i = out.size() - 1; i > 0; i--) {
      int j = (int) below(i + 1);
      T t = out.get(i);
      out.set(i, out.get(j));
      out.set(j, t);
    }
    return out;
  }

  @Override
  public String toString() {
    return "TestData(seed=" + seed + ")";
  }
}
