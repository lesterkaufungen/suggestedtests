import { formatBytes, MemoryUsage, SystemProbe } from "./systemProbe";
import { globalObject } from "./timers";

/** Bytes in a kibibyte. */
export const KiB = 1024;
/** Bytes in a mebibyte. */
export const MiB = 1024 * KiB;
/** Bytes in a gibibyte. */
export const GiB = 1024 * MiB;

const signed = (n: number): string => `${n >= 0 ? "+" : ""}${formatBytes(n)}`;

function collectGarbage(): void {
  // Available with `node --expose-gc` (vitest: `poolOptions.forks.execArgv`).
  (globalObject as { gc?: () => void }).gc?.();
}

/** Memory before and after running a body with {@link measureMemory}. */
export class MemoryReport {
  /**
   * @param before Native sample taken before the body ran.
   * @param after Native sample taken after it completed.
   * @param heapUsedBefore V8 `heapUsed` before the body.
   * @param heapUsedAfter V8 `heapUsed` after the body.
   */
  constructor(
    readonly before: MemoryUsage,
    readonly after: MemoryUsage,
    readonly heapUsedBefore: number,
    readonly heapUsedAfter: number,
  ) {}

  /** Change in resident memory. Can be negative. */
  get rssGrowthBytes(): number {
    return this.after.currentRssBytes - this.before.currentRssBytes;
  }

  /** How far the body pushed the process' peak RSS above its previous peak. */
  get peakGrowthBytes(): number {
    return this.after.peakRssBytes - this.before.peakRssBytes;
  }

  /**
   * Change in V8's used JS heap. Precise only when garbage collection can be
   * forced (`node --expose-gc`); otherwise it includes uncollected garbage.
   */
  get heapGrowthBytes(): number {
    return this.heapUsedAfter - this.heapUsedBefore;
  }

  /** @returns e.g. `MemoryReport(rss: +1.2 MiB, peak: +0 B, heap: +340.0 KiB, now: ...)`. */
  toString(): string {
    return (
      `MemoryReport(rss: ${signed(this.rssGrowthBytes)}, peak: ${signed(this.peakGrowthBytes)}, ` +
      `heap: ${signed(this.heapGrowthBytes)}, now: ${this.after})`
    );
  }
}

/** Budgets of {@link expectMemory}; at least one is required. All in bytes. */
export interface MemoryBudget {
  /** Maximum growth of resident memory. */
  maxRssGrowth?: number;
  /** Maximum rise of the process' peak resident memory. */
  maxPeakGrowth?: number;
  /** Maximum growth of the V8 heap (see {@link MemoryReport.heapGrowthBytes}). */
  maxHeapGrowth?: number;
}

/**
 * Runs `body` and reports how memory changed. RSS (via the native bridge) is
 * a coarse, process-wide signal: use it to catch leaks and blow-ups of
 * megabytes, not to count objects.
 */
export async function measureMemory(body: () => unknown): Promise<MemoryReport> {
  collectGarbage();
  const before = SystemProbe.memoryUsage();
  const heapBefore = process.memoryUsage().heapUsed;
  await body();
  collectGarbage();
  return new MemoryReport(
    before,
    SystemProbe.memoryUsage(),
    heapBefore,
    process.memoryUsage().heapUsed,
  );
}

/**
 * Runs `body` and fails if memory grew more than the given budgets.
 *
 * ```ts
 * test.skipIf(!SystemProbe.isAvailable)("import stays under 50 MiB", async () => {
 *   await expectMemory(() => importAll(rows), { maxPeakGrowth: 50 * MiB });
 * });
 * ```
 */
export async function expectMemory(
  body: () => unknown,
  budget: MemoryBudget,
): Promise<MemoryReport> {
  const entries = Object.entries(budget).filter(([, v]) => v !== undefined) as [string, number][];
  if (entries.length === 0) {
    throw new TypeError("Provide maxRssGrowth, maxPeakGrowth and/or maxHeapGrowth.");
  }
  for (const [name, value] of entries) {
    if (!(value >= 0)) throw new RangeError(`${name} must be >= 0, got ${value}`);
  }
  const report = await measureMemory(body);
  const checks: [number | undefined, number, string][] = [
    [budget.maxRssGrowth, report.rssGrowthBytes, "RSS"],
    [budget.maxPeakGrowth, report.peakGrowthBytes, "peak RSS"],
    [budget.maxHeapGrowth, report.heapGrowthBytes, "JS heap"],
  ];
  for (const [limit, actual, what] of checks) {
    if (limit !== undefined && actual > limit) {
      throw new Error(
        `Memory budget exceeded: ${what} grew ${formatBytes(actual)} > budget ${formatBytes(limit)}\n${report}`,
      );
    }
  }
  return report;
}
