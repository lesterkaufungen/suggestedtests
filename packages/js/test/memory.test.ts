import { describe, expect, test } from "vitest";
import { expectMemory, measureMemory, MemoryReport, MemoryUsage, MiB, SystemProbe } from "../src";

describe("MemoryReport", () => {
  test("growth", () => {
    const r = new MemoryReport(new MemoryUsage(10, 20), new MemoryUsage(15, 30), 100, 50);
    expect([r.rssGrowthBytes, r.peakGrowthBytes, r.heapGrowthBytes]).toEqual([5, 10, -50]);
    expect(String(r)).toMatch(/^MemoryReport\(rss: \+5 B, peak: \+10 B, heap: -50 B/);
  });
});

test("expectMemory validates budgets", async () => {
  await expect(expectMemory(() => {}, {})).rejects.toThrow(TypeError);
  await expect(expectMemory(() => {}, { maxRssGrowth: -1 })).rejects.toThrow(RangeError);
});

describe.skipIf(!SystemProbe.isAvailable)("with the native bridge", () => {
  test("measureMemory reports growth", async () => {
    let keep: Buffer | undefined;
    const report = await measureMemory(() => {
      keep = Buffer.alloc(32 * MiB, 1);
    });
    expect(report.peakGrowthBytes).toBeGreaterThanOrEqual(0);
    expect(keep!.length).toBe(32 * MiB);
  });

  test("expectMemory fails over budget", async () => {
    let keep: Buffer | undefined;
    await expect(
      expectMemory(
        () => {
          keep = Buffer.alloc(128 * MiB, 1);
        },
        { maxPeakGrowth: 0 },
      ),
    ).rejects.toThrow(/Memory budget exceeded: peak RSS grew/);
    expect(keep).toBeDefined();
  });

  test("heap budget", async () => {
    const keep: string[] = [];
    await expect(
      expectMemory(
        () => {
          for (let i = 0; i < 200_000; i++) keep.push(`item ${i}`);
        },
        { maxHeapGrowth: 1024 },
      ),
    ).rejects.toThrow(/JS heap grew/);
  });
});
