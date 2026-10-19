import { formatMs } from "./systemProbe";
import { realTimers, sleep, withCause } from "./timers";

/** Options of {@link eventually}. */
export interface EventuallyOptions {
  /** Give up after this many milliseconds. Default 5000. */
  timeoutMs?: number;
  /** Wait this long between attempts. Default 20. */
  intervalMs?: number;
}

/**
 * Re-runs `body` every `intervalMs` until it returns (or resolves) without
 * throwing, then returns its result. Fails with the last error after
 * `timeoutMs`.
 *
 * Replaces fixed sleeps: the test continues as soon as the condition holds.
 * Waits in real time even when fake timers are installed.
 *
 * ```ts
 * await eventually(() => expect(cache.isWarm).toBe(true));
 * ```
 */
export async function eventually<T>(
  body: () => T | PromiseLike<T>,
  options: EventuallyOptions = {},
): Promise<T> {
  const { timeoutMs = 5000, intervalMs = 20 } = options;
  if (!(timeoutMs >= 0)) throw new RangeError(`timeoutMs must be >= 0, got ${timeoutMs}`);
  if (!(intervalMs >= 0)) throw new RangeError(`intervalMs must be >= 0, got ${intervalMs}`);
  const start = realTimers.hrtime();
  let attempts = 0;
  for (;;) {
    attempts++;
    try {
      return await body();
    } catch (error) {
      if (Number(realTimers.hrtime() - start) / 1e6 >= timeoutMs) {
        throw withCause(
          new Error(
            `Condition not met within ${formatMs(timeoutMs)} (${attempts} attempts). ` +
              `Last error:\n${error instanceof Error ? error.message : String(error)}`,
          ),
          error,
        );
      }
    }
    await sleep(intervalMs);
  }
}
