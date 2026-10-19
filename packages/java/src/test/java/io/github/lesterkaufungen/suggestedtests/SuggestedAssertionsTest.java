package io.github.lesterkaufungen.suggestedtests;

import static io.github.lesterkaufungen.suggestedtests.SuggestedAssertions.*;
import static org.junit.jupiter.api.Assertions.*;

import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;

class SuggestedAssertionsTest {
  @Test
  void uniquePasses() {
    assertUnique(Arrays.asList(1, 2, 3));
    assertUnique(new int[] {1}, new int[] {2});
  }

  @Test
  void duplicateIsNamed() {
    AssertionError e = assertThrows(AssertionError.class, () -> assertUnique(Arrays.asList("a", "b", "c", "b")));
    assertEquals("Expected unique elements, but \"b\" appears at index 1 and 3", e.getMessage());
  }

  @Test
  void arraysAreComparedDeeply() {
    assertThrows(AssertionError.class, () -> assertUnique(new int[] {1}, new int[] {1}));
  }
}
