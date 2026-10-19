package io.github.lesterkaufungen.suggestedtests;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * A test written as given/when/then steps. Each step runs immediately; the value produced by
 * {@code given} is passed to the following steps. A failing step throws a
 * {@link ScenarioStepFailure} naming it.
 *
 * <pre>{@code
 * Scenario.given("an empty cart", Cart::new)
 *     .when("two items are added", cart -> cart.add(10).add(20))
 *     .then("the total is 30", cart -> assertEquals(30, cart.total()));
 * }</pre>
 *
 * @param <T> the value the steps work on
 */
public final class Scenario<T> {
  private final T value;
  private final List<String> passed;

  private Scenario(T value, List<String> passed) {
    this.value = value;
    this.passed = passed;
  }

  private static String label(String keyword, String description) {
    Objects.requireNonNull(description, "description");
    if (description.isEmpty()) throw new IllegalArgumentException("step description must not be empty");
    return keyword + ": " + description;
  }

  /**
   * Runs the setup step and starts a scenario on its result.
   *
   * @param <T> the value type
   * @param description what is being set up
   * @param setup produces the value the other steps work on
   * @return the scenario
   */
  public static <T> Scenario<T> given(String description, ThrowingSupplier<T> setup) {
    String step = label("Given", description);
    List<String> passed = new ArrayList<>();
    T value;
    try {
      value = setup.get();
    } catch (Throwable t) {
      throw new ScenarioStepFailure(step, passed, t);
    }
    passed.add(step);
    return new Scenario<>(value, passed);
  }

  /**
   * Runs a setup step that produces no value; reported as {@code Given: description}.
   * A separate name rather than a {@code given} overload, because Kotlin would
   * pick a void overload for {@code given("x") { Cart() }} and drop the value.
   *
   * @param description what is being set up
   * @param setup the setup code
   * @return the scenario
   */
  public static Scenario<Void> givenThat(String description, ThrowingRunnable setup) {
    return given(
        description,
        () -> {
          setup.run();
          return null;
        });
  }

  private Scenario<T> step(String keyword, String description, ThrowingConsumer<? super T> body) {
    String step = label(keyword, description);
    try {
      body.accept(value);
    } catch (Throwable t) {
      throw new ScenarioStepFailure(step, Collections.unmodifiableList(passed), t);
    }
    passed.add(step);
    return this;
  }

  /**
   * Runs the action under test.
   *
   * @param description the action
   * @param body acts on the value
   * @return this
   */
  public Scenario<T> when(String description, ThrowingConsumer<? super T> body) {
    return step("When", description, body);
  }

  /**
   * Runs an expectation.
   *
   * @param description what is expected
   * @param body asserts on the value
   * @return this
   */
  public Scenario<T> then(String description, ThrowingConsumer<? super T> body) {
    return step("Then", description, body);
  }

  /**
   * Continues the previous step kind (e.g. a second {@code then}).
   *
   * @param description the step
   * @param body works on the value
   * @return this
   */
  public Scenario<T> and(String description, ThrowingConsumer<? super T> body) {
    return step("And", description, body);
  }

  /** @return the value produced by {@code given} */
  public T value() {
    return value;
  }

  /** @return the steps that completed so far */
  public List<String> passedSteps() {
    return Collections.unmodifiableList(new ArrayList<>(passed));
  }
}
