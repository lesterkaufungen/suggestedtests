// The real timer functions, captured when this package is first imported.
// Fake timers (vi.useFakeTimers / jest.useFakeTimers) installed later replace
// the globals, but these keep measuring and waiting in real time.

/** @internal The global object; `globalThis` is missing before Node 12. */
export const globalObject: typeof globalThis =
  typeof globalThis === "object" ? globalThis : (global as typeof globalThis);

/** @internal */
export const realTimers = {
  setTimeout: globalObject.setTimeout.bind(globalObject),
  clearTimeout: globalObject.clearTimeout.bind(globalObject),
  setImmediate: globalObject.setImmediate.bind(globalObject),
  hrtime: process.hrtime.bigint.bind(process.hrtime),
};

/**
 * @internal Sets `error.cause` like `new Error(message, { cause })`, which
 * older engines ignore.
 */
export function withCause<E extends Error>(error: E, cause: unknown): E {
  Object.defineProperty(error, "cause", {
    value: cause,
    writable: true,
    configurable: true,
    enumerable: false,
  });
  return error;
}

/** @internal Resolves after `ms` of real time. */
export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => realTimers.setTimeout(resolve, ms));
}
