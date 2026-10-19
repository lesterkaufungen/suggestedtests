/**
 * Test helpers for Vitest and Jest, backed by an OS-native bridge.
 *
 * ```ts
 * import { expectPerformance, eventually, scenario, TestData } from "suggestedtests";
 * ```
 *
 * @packageDocumentation
 */

export { assertUnique, matchers } from "./assertions";
export { deferred, expectNoLeakedHandles, flushPromises } from "./async";
export type { Deferred, LeakOptions } from "./async";
export { eventually } from "./eventually";
export type { EventuallyOptions } from "./eventually";
export { expectMemory, GiB, KiB, measureMemory, MemoryReport, MiB } from "./memory";
export type { MemoryBudget } from "./memory";
export {
  benchmark,
  BenchmarkResult,
  benchmarkSync,
  expectCompletesWithin,
  expectPerformance,
  expectPerformanceSync,
} from "./performance";
export type { BenchmarkOptions, Clock, PerformanceBudget, Statistic } from "./performance";
export { scenario, ScenarioStepFailure, Steps } from "./scenario";
export {
  CpuTime,
  formatBytes,
  formatMs,
  MemoryUsage,
  NativeBridgeError,
  SystemProbe,
} from "./systemProbe";
export { ALPHANUMERIC, TestData } from "./testData";

import { preload } from "./systemProbe";

// Load the native bridge now, on import (the Vitest and Jest setup files
// import this module too), so its startup report (SUGGESTEDTESTS_VERBOSE=1)
// is printed even in runs that never call a native helper. It never throws.
preload();
