// Types for the matchers registered by "suggestedtests/vitest". An ESM
// declaration (.d.mts): Vitest is ESM-only, so its types must be imported, not required.
import "vitest";

interface SuggestedTestsMatchers<R = unknown> {
  /** Passes if the received iterable has no duplicate elements; names the duplicate's positions otherwise. */
  toHaveUniqueElements(): R;
}

// No type parameters: Vitest 1-4 declare Assertion<T>, Vitest 5 Assertion<R, T>,
// and a declaration may leave out parameters that have defaults (all of them do).
declare module "vitest" {
  interface Assertion extends SuggestedTestsMatchers<void> {}
  interface AsymmetricMatchersContaining extends SuggestedTestsMatchers {}
}

export {};
