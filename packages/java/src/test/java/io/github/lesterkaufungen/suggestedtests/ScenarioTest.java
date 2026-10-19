package io.github.lesterkaufungen.suggestedtests;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Arrays;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.junit.jupiter.api.Test;

class ScenarioTest {
  @Test
  void runsStepsOnTheGivenValue() {
    Scenario<ArrayList<Integer>> s =
        Scenario.given("an empty list", () -> new ArrayList<Integer>())
            .when("two items are added", l -> { l.add(10); l.add(20); })
            .then("it has two items", l -> assertEquals(2, l.size()))
            .and("they sum to 30", l -> assertEquals(30, l.stream().mapToInt(i -> i).sum()));
    assertEquals(Arrays.asList("Given: an empty list", "When: two items are added", "Then: it has two items", "And: they sum to 30"), s.passedSteps());
  }

  @Test
  void failureNamesStep() {
    List<String> later = new ArrayList<>();
    ScenarioStepFailure f =
        assertThrows(
            ScenarioStepFailure.class,
            () -> Scenario.given("setup", () -> 20)
                .then("the total is 30", v -> assertEquals(30, v))
                .and("never", v -> later.add("ran")));
    assertEquals("Then: the total is 30", f.step());
    assertTrue(f.getMessage().startsWith("Then: the total is 30\norg.opentest4j.AssertionFailedError: expected: <30> but was: <20>\nPassed steps:\n  ✓ Given: setup"), f.getMessage());
    assertTrue(later.isEmpty());
    assertNotNull(f.getCause());
  }

  @Test
  void givenWithoutValue() {
    Scenario<Void> s = Scenario.givenThat("the server is up", () -> {});
    assertNull(s.value());
    assertEquals(Collections.singletonList("Given: the server is up"), s.passedSteps());
  }

  @Test
  void validates() {
    assertThrows(IllegalArgumentException.class, () -> Scenario.given("", () -> 1));
  }
}
