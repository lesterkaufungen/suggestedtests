import { withCause } from "./timers";

type Keyword = "Given" | "When" | "Then" | "And";
type StepBody = () => unknown;

/**
 * Builder passed to a {@link scenario} for declaring given/when/then steps.
 * Steps run in declaration order; a failing step is reported by name.
 */
export class Steps {
  private readonly steps: [Keyword, string, StepBody][] = [];

  private add(keyword: Keyword, description: string, body: StepBody): this {
    if (!description) throw new TypeError("step description must not be empty");
    if (typeof body !== "function") throw new TypeError(`${keyword} step needs a function`);
    this.steps.push([keyword, description, body]);
    return this;
  }

  /** Declares setup / preconditions. */
  given(description: string, body: StepBody): this {
    return this.add("Given", description, body);
  }

  /** Declares the action under test. */
  when(description: string, body: StepBody): this {
    return this.add("When", description, body);
  }

  /** Declares an expectation. */
  then(description: string, body: StepBody): this {
    return this.add("Then", description, body);
  }

  /** Continues the previous step kind (e.g. a second `then`). */
  and(description: string, body: StepBody): this {
    return this.add("And", description, body);
  }

  /** Runs the declared steps in order. */
  async run(): Promise<void> {
    if (this.steps.length === 0) throw new Error("scenario declared no steps");
    for (const [keyword, description, body] of this.steps) {
      try {
        await body();
      } catch (error) {
        throw new ScenarioStepFailure(keyword, description, error);
      }
    }
  }
}

/** Thrown when a scenario step fails. The original error is its `cause`. */
export class ScenarioStepFailure extends Error {
  override readonly name = "ScenarioStepFailure";
  /** The error thrown by the step. */
  declare readonly cause: unknown;

  /**
   * @param keyword `Given`, `When`, `Then` or `And`.
   * @param description The step description.
   * @param cause The error thrown by the step.
   */
  constructor(
    readonly keyword: Keyword,
    readonly description: string,
    cause: unknown,
  ) {
    super(`${keyword}: ${description}\n${cause instanceof Error ? cause.message : String(cause)}`);
    withCause(this, cause);
    if (cause instanceof Error && cause.stack) {
      this.stack = `${this.name}: ${keyword}: ${description}\n${cause.stack}`;
    }
  }
}

/**
 * Returns a test body written as given/when/then steps. Works with any
 * runner (`test`/`it` from Vitest, Jest, node:test or Mocha).
 *
 * ```ts
 * test("adding items updates the total", scenario((s) => {
 *   let cart: Cart;
 *   s.given("an empty cart", () => { cart = new Cart(); });
 *   s.when("two items are added", () => cart.add(10).add(20));
 *   s.then("the total is 30", () => expect(cart.total).toBe(30));
 * }));
 * ```
 */
export function scenario(declare: (s: Steps) => void): () => Promise<void> {
  if (typeof declare !== "function") throw new TypeError("scenario needs a function");
  return () => {
    const steps = new Steps();
    declare(steps);
    return steps.run();
  };
}
