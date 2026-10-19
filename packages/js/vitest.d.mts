// Types for the matchers registered by "suggestedtests/vitest". An ESM
// declaration (.d.mts): Vitest is ESM-only, so its types must be imported, not required.
import "vitest";

interface SuggestedTestsMatchers<R = unknown> {
  /** Passes if the received iterable has no duplicate elements; names the duplicate's positions otherwise. */
  toHaveUniqueElements(): R;
}

declare module "vitest" {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  interface Assertion<T = any> extends SuggestedTestsMatchers<T> {}
  interface AsymmetricMatchersContaining extends SuggestedTestsMatchers {}
}

export {};
