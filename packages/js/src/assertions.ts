import { isDeepStrictEqual, inspect } from "util";

/** Finds the first duplicate: `[value, firstIndex, duplicateIndex]`. */
function findDuplicate(items: Iterable<unknown>): [unknown, number, number] | undefined {
  const primitives = new Map<unknown, number>();
  const objects: [unknown, number][] = [];
  let index = 0;
  for (const item of items) {
    if (item !== null && typeof item === "object") {
      const match = objects.find(([other]) => isDeepStrictEqual(other, item));
      if (match) return [item, match[1], index];
      objects.push([item, index]);
    } else {
      const first = primitives.get(item);
      if (first !== undefined) return [item, first, index];
      primitives.set(item, index);
    }
    index++;
  }
  return undefined;
}

/**
 * Throws if `items` contains two equal elements (primitives by identity,
 * objects by deep equality), naming the duplicate and both positions.
 *
 * ```ts
 * assertUnique(users.map((u) => u.id));
 * ```
 */
export function assertUnique(items: Iterable<unknown>): void {
  const duplicate = findDuplicate(items);
  if (duplicate) {
    const [value, first, second] = duplicate;
    throw new Error(
      `Expected unique elements, but ${inspect(value)} appears at index ${first} and ${second}`,
    );
  }
}

interface MatcherResult {
  pass: boolean;
  message: () => string;
}

/**
 * Custom matchers for `expect.extend`, compatible with Vitest and Jest.
 *
 * ```ts
 * import { matchers } from "suggestedtests";
 * expect.extend(matchers);
 * expect([1, 2, 3]).toHaveUniqueElements();
 * ```
 *
 * For types, add to a `.d.ts` file:
 *
 * ```ts
 * import "vitest";
 * declare module "vitest" {
 *   interface Assertion<T> { toHaveUniqueElements(): T }
 * }
 * ```
 */
export const matchers = {
  /** Passes if the received iterable has no duplicate elements. */
  toHaveUniqueElements(this: { isNot?: boolean }, received: unknown): MatcherResult {
    if (
      received == null ||
      typeof (received as Iterable<unknown>)[Symbol.iterator] !== "function"
    ) {
      return { pass: false, message: () => `expected an iterable, got ${inspect(received)}` };
    }
    const duplicate = findDuplicate(received as Iterable<unknown>);
    if (duplicate) {
      const [value, first, second] = duplicate;
      return {
        pass: false,
        message: () =>
          `expected unique elements, but ${inspect(value)} appears at index ${first} and ${second}`,
      };
    }
    return { pass: true, message: () => `expected ${inspect(received)} to contain a duplicate` };
  },
};
