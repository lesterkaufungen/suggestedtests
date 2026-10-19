import { afterEach, expect, test, vi } from "vitest";
import { eventually } from "../src";

afterEach(() => {
  vi.useRealTimers();
});

test("returns once the condition holds", async () => {
  let n = 0;
  await expect(
    eventually(() => (++n >= 3 ? n : Promise.reject(new Error("no"))), { intervalMs: 1 }),
  ).resolves.toBe(3);
});

test("fails with the last error", async () => {
  await expect(
    eventually(
      () => {
        throw new Error("boom");
      },
      { timeoutMs: 30 },
    ),
  ).rejects.toThrow(/^Condition not met within 30\.00ms \(\d+ attempts\)\. Last error:\nboom$/);
});

test("keeps polling in real time under fake timers", async () => {
  vi.useFakeTimers();
  let n = 0;
  await expect(
    eventually(
      () => {
        if (++n < 3) throw new Error("not yet");
        return n;
      },
      { intervalMs: 1 },
    ),
  ).resolves.toBe(3);
});

test("validates options", async () => {
  await expect(eventually(() => 1, { timeoutMs: -1 })).rejects.toThrow(RangeError);
  await expect(eventually(() => 1, { intervalMs: Number.NaN })).rejects.toThrow(RangeError);
});
