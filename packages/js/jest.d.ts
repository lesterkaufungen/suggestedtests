// Types for the matchers registered by "suggestedtests/jest", for both the
// global `expect` (@types/jest) and `import { expect } from "@jest/globals"`.

interface SuggestedTestsMatchers<R> {
  /** Passes if the received iterable has no duplicate elements; names the duplicate's positions otherwise. */
  toHaveUniqueElements(): R;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace jest {
    interface Matchers<R, T = {}> extends SuggestedTestsMatchers<R> {}
  }
}

declare module "expect" {
  interface Matchers<
    R extends void | Promise<void>,
    T = unknown,
  > extends SuggestedTestsMatchers<R> {}
}

export {};
