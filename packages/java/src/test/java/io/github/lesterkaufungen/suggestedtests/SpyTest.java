package io.github.lesterkaufungen.suggestedtests;

import static io.github.lesterkaufungen.suggestedtests.SuggestedAssertions.*;
import static org.junit.jupiter.api.Assertions.*;

import java.util.Arrays;
import java.util.List;
import java.util.function.BiFunction;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Supplier;
import org.junit.jupiter.api.Test;

class SpyTest {
  @Test
  void recordsAndDelegates() {
    Spy<Function<String, Integer>> parse = Spy.function(Integer::parseInt);
    assertNotCalled(parse);
    assertEquals(42, parse.get().apply("42"));
    parse.get().apply("7");
    assertEquals(Arrays.asList(Arrays.asList("42"), Arrays.asList("7")), parse.calls());
    assertEquals(Arrays.asList("7"), parse.lastCall());
    assertCalled(parse);
    assertCalledTimes(parse, 2);
    assertCalledWith(parse, "42");
    assertCalledWith(parse, argThat("a number", (String s) -> s.matches("\\d+")));
    parse.reset();
    assertEquals(0, parse.callCount());
  }

  @Test
  void consumerAndRunnable() {
    Spy<Consumer<String>> onChange = Spy.consumer();
    Arrays.asList("a", "b").forEach(onChange.get());
    assertCalledWith(onChange, "b");
    Spy<Runnable> r = Spy.runnable();
    r.get().run();
    assertCalledTimes(r, 1);
  }

  @Test
  void anyInterfaceDefaultsToZeroValues() {
    Spy<BiFunction<Integer, Integer, Integer>> add = Spy.of(castClass(BiFunction.class), null);
    assertNull(add.get().apply(1, 2));
    assertCalledWith(add, any(), 2);
    Spy<java.util.function.IntSupplier> zero = Spy.of(java.util.function.IntSupplier.class, null);
    assertEquals(0, zero.get().getAsInt());
  }

  @SuppressWarnings("unchecked")
  private static <T> Class<T> castClass(Class<?> c) {
    return (Class<T>) c;
  }

  @Test
  void exceptionsFromImplPropagate() {
    Spy<Supplier<String>> s = Spy.supplier(() -> { throw new IllegalStateException("x"); });
    assertThrows(IllegalStateException.class, () -> s.get().get());
    assertCalledTimes(s, 1);
  }

  @Test
  void calledWithFailureListsCalls() {
    Spy<Consumer<String>> s = Spy.consumer();
    s.get().accept("hello");
    AssertionError e = assertThrows(AssertionError.class, () -> assertCalledWith(s, "bye"));
    assertEquals("Expected the spy to be called with [bye], but it was called 1 time(s): [[hello]]", e.getMessage());
  }

  @Test
  void objectMethodsDontRecord() {
    Spy<Runnable> r = Spy.runnable();
    assertNotNull(r.get().toString());
    assertEquals(r.get(), r.get());
    assertNotCalled(r);
  }

  @Test
  void rejectsNonFunctionalTypes() {
    assertThrows(IllegalArgumentException.class, () -> Spy.of(List.class, null));
    assertThrows(IllegalArgumentException.class, () -> Spy.of(String.class, null));
  }

  @Test
  void lastCallOfUnusedSpyThrows() {
    assertThrows(IllegalStateException.class, () -> Spy.runnable().lastCall());
  }
}
