import * as asyncHooks from "async_hooks";
import { formatMs } from "./systemProbe";
import { realTimers, sleep } from "./timers";

/** A promise with its `resolve` and `reject` exposed. See {@link deferred}. */
export interface Deferred<T> {
  /** The controlled promise. */
  readonly promise: Promise<T>;
  /** Resolves `promise`. */
  resolve(value: T | PromiseLike<T>): void;
  /** Rejects `promise`. */
  reject(reason?: unknown): void;
  /** Whether `resolve` or `reject` has been called. */
  readonly settled: boolean;
}

/**
 * Creates a promise the test settles by hand, to control exactly when async
 * dependencies complete and assert on the states in between.
 *
 * ```ts
 * const response = deferred<User>();
 * api.fetchUser = () => response.promise;
 * const view = render();            // shows a spinner
 * response.resolve({ name: "Ada" });
 * await flushPromises();             // now shows "Ada"
 * ```
 */
export function deferred<T = void>(): Deferred<T> {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  let settled = false;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return {
    promise,
    resolve(value) {
      settled = true;
      resolve(value);
    },
    reject(reason) {
      settled = true;
      reject(reason);
    },
    get settled() {
      return settled;
    },
  };
}

/**
 * Resolves after all currently queued promise callbacks have run (one
 * macrotask turn, using the real `setImmediate` even under fake timers).
 */
export function flushPromises(): Promise<void> {
  return new Promise((resolve) => realTimers.setImmediate(resolve));
}

/** Options of {@link expectNoLeakedHandles}. */
export interface LeakOptions {
  /** How long to wait for handles to close after `body`. Default 100 ms. */
  timeoutMs?: number;
  /** Resource types to ignore, e.g. `["TTYWrap"]`. */
  ignore?: readonly string[];
}

interface ResourceTracker {
  /** Types of the resources still open, e.g. `["Timeout", "TCPServerWrap"]`. */
  open(): string[];
  stop(): void;
}

/**
 * Ignored by the async_hooks fallback: not handles, or process-wide
 * singletons Node creates lazily and never closes (the c-ares DNS channel,
 * Node 10's timer list).
 */
const NOT_LEAKS = new Set([
  "PROMISE",
  "TickObject",
  "Microtask",
  "ELDHISTOGRAM",
  "DNSCHANNEL",
  "TIMERWRAP",
]);

/** Set while the helper creates its own polling timer. */
let creatingOwnTimer = false;

/**
 * Tracks the libuv resources opened from now on. Uses
 * `process.getActiveResourcesInfo()` (Node 17.3+) and otherwise `async_hooks`,
 * which reports every resource's creation and destruction.
 */
function trackResources(ignore: readonly string[]): ResourceTracker {
  const p = process as unknown as { getActiveResourcesInfo?: () => string[] };
  if (typeof p.getActiveResourcesInfo === "function") {
    const count = (): Map<string, number> => {
      const counts = new Map<string, number>();
      for (const type of p.getActiveResourcesInfo!()) counts.set(type, (counts.get(type) ?? 0) + 1);
      return counts;
    };
    const before = count();
    return {
      open() {
        const result: string[] = [];
        for (const [type, n] of count()) {
          for (let i = before.get(type) ?? 0; i < n; i++)
            if (!ignore.includes(type)) result.push(type);
        }
        return result;
      },
      stop() {},
    };
  }
  const live = new Map<number, string>();
  const hook = asyncHooks.createHook({
    init(id, type) {
      if (creatingOwnTimer || NOT_LEAKS.has(type) || ignore.includes(type)) return;
      live.set(id, type);
    },
    destroy(id) {
      live.delete(id);
    },
  });
  hook.enable();
  return {
    open: () => [...live.values()],
    stop: () => hook.disable(),
  };
}

function summarize(types: string[]): string {
  const counts = new Map<string, number>();
  for (const t of types) counts.set(t, (counts.get(t) ?? 0) + 1);
  return [...counts].map(([type, n]) => `${n} × ${type}`).join(", ");
}

/**
 * Runs `body` and fails if it leaves timers, sockets, servers or other
 * libuv handles open — the usual cause of "Jest did not exit" and of tests
 * that interfere with each other. Uses `process.getActiveResourcesInfo()`
 * (Node 17.3+) or, on older Node, `async_hooks`.
 *
 * ```ts
 * test("server shuts down", async () => {
 *   await expectNoLeakedHandles(async () => {
 *     const server = await startServer();
 *     await server.close();
 *   });
 * });
 * ```
 */
export async function expectNoLeakedHandles(
  body: () => unknown,
  options: LeakOptions = {},
): Promise<void> {
  const { timeoutMs = 100, ignore = [] } = options;
  if (!(timeoutMs >= 0)) throw new RangeError(`timeoutMs must be >= 0, got ${timeoutMs}`);
  const tracker = trackResources(ignore);
  try {
    await body();
    const start = realTimers.hrtime();
    for (;;) {
      const open = tracker.open();
      if (open.length === 0) return;
      if (Number(realTimers.hrtime() - start) / 1e6 >= timeoutMs) {
        throw new Error(
          `Handles still open ${formatMs(timeoutMs)} after the body finished: ${summarize(open)}`,
        );
      }
      creatingOwnTimer = true;
      const wait = sleep(5); // init hooks run synchronously inside setTimeout
      creatingOwnTimer = false;
      await wait;
    }
  } finally {
    tracker.stop();
  }
}
