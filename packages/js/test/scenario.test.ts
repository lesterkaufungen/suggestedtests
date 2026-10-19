import { expect, test } from "vitest";
import { scenario, ScenarioStepFailure, Steps } from "../src";

test(
  "runs steps in order",
  scenario((s) => {
    const log: string[] = [];
    s.given("a", () => void log.push("a"));
    s.when("b", async () => void log.push("b"));
    s.then("c", () => expect(log).toEqual(["a", "b"]));
    s.and("d", () => expect(log).toHaveLength(2));
  }),
);

test("names the failing step", async () => {
  const s = new Steps().given("setup", () => {}).then("the total is 30", () => expect(20).toBe(30));
  const error = await s.run().catch((e: unknown) => e);
  expect(error).toBeInstanceOf(ScenarioStepFailure);
  const failure = error as ScenarioStepFailure;
  expect(failure.keyword).toBe("Then");
  expect(failure.description).toBe("the total is 30");
  expect(failure.message).toMatch(/^Then: the total is 30\n.*expected 20 to be 30/);
  expect(failure.cause).toBeInstanceOf(Error);
});

test("later steps don't run after a failure", async () => {
  let ran = false;
  const s = new Steps()
    .when("it breaks", () => {
      throw new Error("x");
    })
    .then("never", () => {
      ran = true;
    });
  await expect(s.run()).rejects.toThrow("When: it breaks");
  expect(ran).toBe(false);
});

test("validates", async () => {
  await expect(new Steps().run()).rejects.toThrow("no steps");
  expect(() => new Steps().given("", () => {})).toThrow(TypeError);
  expect(() => new Steps().given("x", undefined as never)).toThrow(TypeError);
  expect(() => scenario(undefined as never)).toThrow(TypeError);
});
