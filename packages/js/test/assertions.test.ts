/// <reference types="../vitest.d.mts" />
import { expect, test } from "vitest";
import { assertUnique, matchers } from "../src";

expect.extend(matchers);

test("assertUnique passes", () => {
  assertUnique([1, 2, 3]);
  assertUnique(new Set(["a", "b"]));
  assertUnique([{ id: 1 }, { id: 2 }]);
});

test("assertUnique names the duplicate", () => {
  expect(() => assertUnique(["a", "b", "c", "b"])).toThrow(
    "Expected unique elements, but 'b' appears at index 1 and 3",
  );
  expect(() => assertUnique([{ id: 1 }, { id: 1 }])).toThrow("{ id: 1 } appears at index 0 and 1");
});

test("toHaveUniqueElements matcher", () => {
  expect([1, 2, 3]).toHaveUniqueElements();
  expect([1, 2, 1]).not.toHaveUniqueElements();
  expect(() => expect([1, 1]).toHaveUniqueElements()).toThrow("1 appears at index 0 and 1");
  expect(() => expect(42).toHaveUniqueElements()).toThrow("expected an iterable");
});
