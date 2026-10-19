import { afterEach, describe, expect, test, vi } from "vitest";
import {
  benchmark,
  BenchmarkResult,
  benchmarkSync,
  expectCompletesWithin,
  expectPerformance,
  expectPerformanceSync,
  SystemProbe,
} from "../src";

afterEach(() => {
  vi.useRealTimers();
});

describe("BenchmarkResult", () => {
  const r = new BenchmarkResult("r", [5, 1, 3, 2, 4]);

  test("statistics", () => {
    expect([r.min, r.max, r.mean, r.median, r.p95]).toEqual([1, 5, 3, 3, 5]);
    expect(r.get("median")).toBe(3);
    expect(r.percentile(0)).toBe(1);
    expect(r.stdDev).toBeCloseTo(Math.SQRT2);
    expect(r.samples).toEqual([5, 1, 3, 2, 4]);
  });

  test("validates", () => {
    expect(() => new BenchmarkResult("r", [])).toThrow(RangeError);
    expect(() => r.percentile(101)).toThrow(RangeError);
    expect(() => r.get("p99" as never)).toThrow(RangeError);
  });

  test("toString", () => {
    expect(String(new BenchmarkResult("x", [0.5, 2.5, 3000]))).toMatch(
      /^x: n=3 min=500µs median=2\.50ms mean=1\.00s/,
    );
  });
});

describe("benchmark", () => {
  test("counts runs", async () => {
    let calls = 0;
    const r = await benchmark("b", () => calls++, { iterations: 5, warmup: 2 });
    expect(calls).toBe(7);
    expect(r.samples).toHaveLength(5);
  });

  test("sync variant", () => {
    let calls = 0;
    expect(
      benchmarkSync("b", () => void calls++, { iterations: 4, warmup: 0 }).samples,
    ).toHaveLength(4);
    expect(calls).toBe(4);
  });

  test.each([
    { iterations: 0 },
    { warmup: -1 },
    { iterations: 1.5 },
    { clock: "sundial" as never },
  ])("rejects %o", (options) => {
    expect(() => benchmarkSync("b", () => {}, options)).toThrow(RangeError);
  });

  test("measures real time under fake timers", async () => {
    vi.useFakeTimers();
    // Fake time stands still; the busy loop still takes real time.
    const r = benchmarkSync("busy", () => JSON.stringify(Array(10_000).fill("x")), {
      iterations: 1,
      warmup: 0,
    });
    expect(r.samples[0]).toBeGreaterThan(0);
  });

  test.skipIf(!SystemProbe.isAvailable)("cpu clock ignores waiting", async () => {
    const r = await benchmark("sleep", () => new Promise((res) => setTimeout(res, 10)), {
      iterations: 3,
      warmup: 0,
      clock: "cpu",
    });
    expect(r.clock).toBe("cpu");
    expect(r.median).toBeLessThan(8);
  });
});

describe("expectPerformance", () => {
  test("passes within budget", async () => {
    const r = await expectPerformance(() => {}, { budgetMs: 1000 });
    expect(r.name).toBe("benchmark");
  });

  test("fails over budget", () => {
    expect(() =>
      expectPerformanceSync(() => JSON.stringify(Array(1000).fill(1)), {
        budgetMs: 0,
        statistic: "max",
        iterations: 2,
        name: "json",
      }),
    ).toThrow(/Performance budget exceeded: max .* > budget 0µs\njson: n=2/);
  });

  test("validates before running", async () => {
    let calls = 0;
    await expect(expectPerformance(() => calls++, { budgetMs: -1 })).rejects.toThrow(RangeError);
    await expect(
      expectPerformance(() => calls++, { budgetMs: 1, statistic: "p42" as never }),
    ).rejects.toThrow(RangeError);
    await expect(expectPerformance(() => calls++, { budgetMs: 1, iterations: 0 })).rejects.toThrow(
      RangeError,
    );
    expect(calls).toBe(0);
  });
});

describe("expectCompletesWithin", () => {
  test("returns the value", async () => {
    await expect(expectCompletesWithin(Promise.resolve(42), 100)).resolves.toBe(42);
  });

  test("fails when too slow", async () => {
    await expect(expectCompletesWithin(new Promise(() => {}), 10)).rejects.toThrow(
      "Promise did not complete within 10.00ms",
    );
  });

  test("propagates rejections", async () => {
    await expect(expectCompletesWithin(Promise.reject(new Error("boom")), 100)).rejects.toThrow(
      "boom",
    );
  });

  test("validates the limit", async () => {
    await expect(expectCompletesWithin(Promise.resolve(), -1)).rejects.toThrow(RangeError);
  });
});
