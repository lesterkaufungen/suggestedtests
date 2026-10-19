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
  /** Called when the body has finished: resources created later aren't its own. */
  bodyFinished(): void;
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

/**
 * The `getActiveResourcesInfo()` names of async_hooks resource types (the
 * same on Node 18 and 24). Only these are matched by identity on Node 17.3+.
 */
const RESOURCE_NAMES = new Map([
  ["Timeout", "Timeout"],
  ["Immediate", "Immediate"],
  ["TCPSERVERWRAP", "TCPServerWrap"],
  ["TCPWRAP", "TCPSocketWrap"],
  ["PIPESERVERWRAP", "PipeWrap"],
  ["PIPEWRAP", "PipeWrap"],
  ["UDPWRAP", "UDPWrap"],
  ["PROCESSWRAP", "ProcessWrap"],
  ["FSEVENTWRAP", "FSEventWrap"],
  ["STATWATCHER", "StatWatcher"],
  ["GETADDRINFOREQWRAP", "GetAddrInfoReqWrap"],
]);

function countTypes(types: readonly string[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const type of types) counts.set(type, (counts.get(type) ?? 0) + 1);
  return counts;
}

/**
 * Tracks the libuv resources the body opens. `async_hooks` reports each
 * resource's creation and destruction; on Node 17.3+ the result is also
 * checked against `process.getActiveResourcesInfo()`, whose names it uses.
 */
function trackResources(ignore: readonly string[]): ResourceTracker {
  // The resources created while the body runs, until they are destroyed.
  const created = new Map<number, { type: string; resource: { hasRef?: () => boolean } }>();
  let recording = true;
  const hook = asyncHooks.createHook({
    init(id, type, _trigger, resource) {
      if (recording && !NOT_LEAKS.has(type)) created.set(id, { type, resource });
    },
    destroy(id) {
      created.delete(id);
    },
  });
  hook.enable();
  // Unref'd handles don't keep the process alive, so they aren't leaks.
  const live = (): string[] =>
    [...created.values()]
      .filter(({ resource }) => typeof resource.hasRef !== "function" || resource.hasRef())
      .map(({ type }) => type);
  const tracker = {
    bodyFinished: () => {
      recording = false;
    },
    open: () => live().filter((type) => !ignore.includes(type)),
    stop: () => hook.disable(),
  };
  const p = process as unknown as { getActiveResourcesInfo?: () => string[] };
  if (typeof p.getActiveResourcesInfo !== "function") return tracker;
  const before = countTypes(p.getActiveResourcesInfo());
  return {
    ...tracker,
    open() {
      const own = countTypes(
        live()
          .map((type) => RESOURCE_NAMES.get(type))
          .filter((name): name is string => name !== undefined),
      );
      const result: string[] = [];
      for (const [name, n] of countTypes(p.getActiveResourcesInfo!())) {
        if (ignore.includes(name)) continue;
        // When the runner closes a handle of the same type meanwhile, the
        // difference alone hides one the body left open; the body's own live
        // resources are a lower bound (capped, so Node counts each of them).
        const leaked = Math.max(n - (before.get(name) ?? 0), Math.min(own.get(name) ?? 0, n));
        for (let i = 0; i < leaked; i++) result.push(name);
      }
      return result;
    },
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
    tracker.bodyFinished();
    const start = realTimers.hrtime();
    for (;;) {
      const open = tracker.open();
      if (open.length === 0) return;
      if (Number(realTimers.hrtime() - start) / 1e6 >= timeoutMs) {
        throw new Error(
          `Handles still open ${formatMs(timeoutMs)} after the body finished: ${summarize(open)}`,
        );
      }
      await sleep(5);
    }
  } finally {
    tracker.stop();
  }
}
