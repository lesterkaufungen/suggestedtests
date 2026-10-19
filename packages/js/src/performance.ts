import { formatMs, SystemProbe } from "./systemProbe";
import { realTimers } from "./timers";

/** Which statistic of a {@link BenchmarkResult} a budget is checked against. */
export type Statistic = "min" | "mean" | "median" | "p95" | "max";

const STATISTICS: readonly Statistic[] = ["min", "mean", "median", "p95", "max"];

/**
 * What a benchmark measures:
 * - `"wall"`: elapsed time (`process.hrtime`). Includes waiting and time
 *   stolen by other processes.
 * - `"cpu"`: CPU time via the native bridge. Ignores waiting and other
 *   processes, so it is far less noisy on busy CI machines.
 *   {@link benchmarkSync} measures the calling thread; {@link benchmark}
 *   measures the whole process, because awaited work may run on libuv's
 *   thread pool.
 */
export type Clock = "wall" | "cpu";

/** Options shared by the benchmark functions. */
export interface BenchmarkOptions {
  /** Timed runs. Default 20. */
  iterations?: number;
  /** Untimed runs before the timed ones. Default 3. */
  warmup?: number;
  /** What to measure. Default `"wall"`. */
  clock?: Clock;
}

/** Options of {@link expectPerformance} and {@link expectPerformanceSync}. */
export interface PerformanceBudget extends BenchmarkOptions {
  /** Maximum allowed value of `statistic`, in milliseconds. */
  budgetMs: number;
  /** Statistic checked against the budget. Default `"median"`. */
  statistic?: Statistic;
  /** Label used in the failure message. Default `"benchmark"`. */
  name?: string;
}

/** Timing statistics collected by {@link benchmark} or {@link benchmarkSync}. All durations are in milliseconds. */
export class BenchmarkResult {
  /** Measured durations in run order (warm-up runs excluded). */
  readonly samples: readonly number[];
  private readonly sorted: readonly number[];

  /**
   * @param name Label of the benchmark.
   * @param samples Durations in milliseconds; must not be empty.
   * @param clock What the samples measure.
   */
  constructor(
    readonly name: string,
    samples: readonly number[],
    readonly clock: Clock = "wall",
  ) {
    if (samples.length === 0) throw new RangeError("samples must not be empty");
    this.samples = Object.freeze([...samples]);
    this.sorted = Object.freeze([...samples].sort((a, b) => a - b));
  }

  /** Fastest sample. */
  get min(): number {
    return this.sorted[0]!;
  }

  /** Slowest sample. */
  get max(): number {
    return this.sorted[this.sorted.length - 1]!;
  }

  /** Arithmetic mean. */
  get mean(): number {
    return this.samples.reduce((s, x) => s + x, 0) / this.samples.length;
  }

  /** Median (50th percentile). */
  get median(): number {
    return this.percentile(50);
  }

  /** 95th percentile. */
  get p95(): number {
    return this.percentile(95);
  }

  /** Population standard deviation of the samples. */
  get stdDev(): number {
    const m = this.mean;
    return Math.sqrt(this.samples.reduce((s, x) => s + (x - m) ** 2, 0) / this.samples.length);
  }

  /** The `p`th percentile (0–100) using nearest-rank. */
  percentile(p: number): number {
    if (!(p >= 0 && p <= 100)) throw new RangeError(`p must be in [0, 100], got ${p}`);
    const rank = Math.min(
      Math.max(Math.ceil((p / 100) * this.sorted.length), 1),
      this.sorted.length,
    );
    return this.sorted[rank - 1]!;
  }

  /** The value of `statistic`. */
  get(statistic: Statistic): number {
    checkStatistic(statistic);
    return this[statistic];
  }

  /** @returns e.g. `parse: n=20 min=1.02ms median=1.10ms ...`. */
  toString(): string {
    return (
      `${this.name}${this.clock === "cpu" ? " (cpu)" : ""}: n=${this.samples.length} ` +
      `min=${formatMs(this.min)} median=${formatMs(this.median)} mean=${formatMs(this.mean)} ` +
      `p95=${formatMs(this.p95)} max=${formatMs(this.max)} ±${formatMs(this.stdDev)}`
    );
  }
}

function checkStatistic(statistic: string): asserts statistic is Statistic {
  if (!STATISTICS.includes(statistic as Statistic)) {
    throw new RangeError(`statistic must be one of ${STATISTICS.join(", ")}, got ${statistic}`);
  }
}

function counts(options: BenchmarkOptions): { iterations: number; warmup: number; clock: Clock } {
  const { iterations = 20, warmup = 3, clock = "wall" } = options;
  if (!Number.isInteger(iterations) || iterations < 1) {
    throw new RangeError(`iterations must be an integer >= 1, got ${iterations}`);
  }
  if (!Number.isInteger(warmup) || warmup < 0) {
    throw new RangeError(`warmup must be an integer >= 0, got ${warmup}`);
  }
  if (clock !== "wall" && clock !== "cpu") {
    throw new RangeError(`clock must be "wall" or "cpu", got ${String(clock)}`);
  }
  return { iterations, warmup, clock };
}

/** Returns a function reading `clock` in nanoseconds. */
function reader(clock: Clock, sync: boolean): () => number {
  if (clock === "wall") {
    const hrtime = realTimers.hrtime;
    return () => Number(hrtime());
  }
  if (!SystemProbe.isAvailable) {
    throw new Error(`clock "cpu" needs the native bridge: ${SystemProbe.skipReason}`);
  }
  return sync ? SystemProbe.threadCpuTimeNs : () => SystemProbe.processCpuTime().totalNs;
}

/**
 * Runs `body` `warmup` times untimed, then `iterations` times timed, awaiting
 * it each time. Uses the real clock even when fake timers are installed.
 *
 * ```ts
 * const result = await benchmark("load", () => repository.load());
 * console.log(String(result)); // load: n=20 min=1.02ms median=1.10ms ...
 * ```
 */
export async function benchmark(
  name: string,
  body: () => unknown,
  options: BenchmarkOptions = {},
): Promise<BenchmarkResult> {
  const { iterations, warmup, clock } = counts(options);
  const now = reader(clock, false);
  for (let i = 0; i < warmup; i++) await body();
  const samples: number[] = [];
  for (let i = 0; i < iterations; i++) {
    const start = now();
    await body();
    samples.push((now() - start) / 1e6);
  }
  return new BenchmarkResult(name, samples, clock);
}

/** Synchronous {@link benchmark}. No microtask hop between runs, so it is more precise for very fast code. */
export function benchmarkSync(
  name: string,
  body: () => void,
  options: BenchmarkOptions = {},
): BenchmarkResult {
  const { iterations, warmup, clock } = counts(options);
  const now = reader(clock, true);
  for (let i = 0; i < warmup; i++) body();
  const samples: number[] = [];
  for (let i = 0; i < iterations; i++) {
    const start = now();
    body();
    samples.push((now() - start) / 1e6);
  }
  return new BenchmarkResult(name, samples, clock);
}

function checkBudget(budget: PerformanceBudget): Statistic {
  if (!(budget.budgetMs >= 0)) {
    throw new RangeError(`budgetMs must be >= 0, got ${budget.budgetMs}`);
  }
  const statistic = budget.statistic ?? "median";
  checkStatistic(statistic);
  counts(budget);
  return statistic;
}

function verify(result: BenchmarkResult, statistic: Statistic, budgetMs: number): BenchmarkResult {
  const actual = result.get(statistic);
  if (actual > budgetMs) {
    throw new Error(
      `Performance budget exceeded: ${statistic} ${formatMs(actual)} > budget ${formatMs(budgetMs)}\n${result}`,
    );
  }
  return result;
}

/**
 * Benchmarks `body` and fails if the chosen statistic exceeds `budgetMs`.
 * Returns the result so it can be logged.
 *
 * ```ts
 * test("parsing stays fast", async () => {
 *   await expectPerformance(() => parse(bigJson), { budgetMs: 5 });
 * });
 * ```
 */
export async function expectPerformance(
  body: () => unknown,
  budget: PerformanceBudget,
): Promise<BenchmarkResult> {
  const statistic = checkBudget(budget);
  const result = await benchmark(budget.name ?? "benchmark", body, budget);
  return verify(result, statistic, budget.budgetMs);
}

/** Synchronous {@link expectPerformance}. */
export function expectPerformanceSync(
  body: () => void,
  budget: PerformanceBudget,
): BenchmarkResult {
  const statistic = checkBudget(budget);
  return verify(
    benchmarkSync(budget.name ?? "benchmark", body, budget),
    statistic,
    budget.budgetMs,
  );
}

/**
 * Awaits `promise` and fails unless it settles successfully within `limitMs`
 * of real time. Returns its value.
 *
 * ```ts
 * const user = await expectCompletesWithin(repository.load(), 1000);
 * ```
 */
export async function expectCompletesWithin<T>(
  promise: PromiseLike<T>,
  limitMs: number,
): Promise<T> {
  if (!(limitMs >= 0)) throw new RangeError(`limitMs must be >= 0, got ${limitMs}`);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = realTimers.setTimeout(
      () => reject(new Error(`Promise did not complete within ${formatMs(limitMs)}`)),
      limitMs,
    );
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    realTimers.clearTimeout(timer);
  }
}
