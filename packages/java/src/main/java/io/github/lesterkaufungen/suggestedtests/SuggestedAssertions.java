package io.github.lesterkaufungen.suggestedtests;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
import java.util.function.Predicate;

/**
 * Assertions JUnit doesn't have built in. Import statically:
 *
 * <pre>{@code
 * import static io.github.lesterkaufungen.suggestedtests.SuggestedAssertions.*;
 * }</pre>
 */
public final class SuggestedAssertions {
  private SuggestedAssertions() {}

  /**
   * Fails if {@code items} contains two equal elements ({@link Objects#deepEquals}), naming
   * the duplicate and both positions.
   *
   * @param items the elements
   */
  public static void assertUnique(Iterable<?> items) {
    List<Object> seen = new ArrayList<>();
    int index = 0;
    for (Object item : items) {
      for (int i = 0; i < seen.size(); i++) {
        if (Objects.deepEquals(seen.get(i), item)) {
          throw new AssertionError(
              "Expected unique elements, but " + describe(item) + " appears at index " + i + " and " + index);
        }
      }
      seen.add(item);
      index++;
    }
  }

  /**
   * Array variant of {@link #assertUnique(Iterable)}.
   *
   * @param items the elements
   */
  public static void assertUnique(Object... items) {
    assertUnique(Arrays.asList(items));
  }

  private static String describe(Object value) {
    if (value instanceof String) return "\"" + value + "\"";
    if (value instanceof Object[]) return Arrays.deepToString((Object[]) value);
    return String.valueOf(value);
  }

  /** An argument pattern for {@link #assertCalledWith}; build with {@link #argThat}. */
  public static final class ArgumentMatcher {
    private final String description;
    private final Predicate<Object> predicate;

    private ArgumentMatcher(String description, Predicate<Object> predicate) {
      this.description = description;
      this.predicate = predicate;
    }

    @Override
    public String toString() {
      return description;
    }
  }

  /** @return a matcher accepting any argument */
  public static ArgumentMatcher any() {
    return new ArgumentMatcher("<any>", v -> true);
  }

  /**
   * @param <T> the expected argument type
   * @param description shown in failure messages
   * @param predicate accepts matching arguments; a {@link ClassCastException} counts as no match
   * @return a matcher
   */
  @SuppressWarnings("unchecked")
  public static <T> ArgumentMatcher argThat(String description, Predicate<T> predicate) {
    return new ArgumentMatcher(
        "<" + description + ">",
        v -> {
          try {
            return predicate.test((T) v);
          } catch (ClassCastException e) {
            return false;
          }
        });
  }

  /**
   * Fails unless {@code spy} was called at least once.
   *
   * @param spy the spy
   */
  public static void assertCalled(Spy<?> spy) {
    if (!spy.called()) throw new AssertionError("Expected the spy to be called, but it never was.");
  }

  /**
   * Fails if {@code spy} was called.
   *
   * @param spy the spy
   */
  public static void assertNotCalled(Spy<?> spy) {
    assertCalledTimes(spy, 0);
  }

  /**
   * Fails unless {@code spy} was called exactly {@code times} times.
   *
   * @param spy the spy
   * @param times expected number of calls
   */
  public static void assertCalledTimes(Spy<?> spy, int times) {
    if (spy.callCount() != times) {
      throw new AssertionError("Expected the spy to be called " + times + " time(s), but: " + spy);
    }
  }

  /**
   * Fails unless {@code spy} has a call whose arguments match {@code args}: each is a value
   * (compared with {@link Objects#deepEquals}) or a matcher from {@link #any()} / {@link #argThat}.
   *
   * @param spy the spy
   * @param args the expected arguments
   */
  public static void assertCalledWith(Spy<?> spy, Object... args) {
    for (List<Object> call : spy.calls()) {
      if (call.size() != args.length) continue;
      boolean match = true;
      for (int i = 0; i < args.length && match; i++) {
        match =
            args[i] instanceof ArgumentMatcher
                ? ((ArgumentMatcher) args[i]).predicate.test(call.get(i))
                : Objects.deepEquals(args[i], call.get(i));
      }
      if (match) return;
    }
    throw new AssertionError(
        "Expected the spy to be called with " + Arrays.toString(args) + ", but it was called "
            + spy.callCount() + " time(s): " + spy.calls());
  }
}
