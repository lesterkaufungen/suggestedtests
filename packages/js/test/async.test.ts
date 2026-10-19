import { createServer } from "node:net";
import { afterEach, expect, test, vi } from "vitest";
import { deferred, expectNoLeakedHandles, flushPromises } from "../src";

afterEach(() => {
  vi.useRealTimers();
});

test("deferred resolves by hand", async () => {
  const d = deferred<number>();
  let value: number | undefined;
  void d.promise.then((v) => (value = v));
  await flushPromises();
  expect(value).toBeUndefined();
  expect(d.settled).toBe(false);
  d.resolve(7);
  expect(d.settled).toBe(true);
  await flushPromises();
  expect(value).toBe(7);
});

test("deferred rejects by hand", async () => {
  const d = deferred();
  d.reject(new Error("nope"));
  await expect(d.promise).rejects.toThrow("nope");
});

test("flushPromises works under fake timers", async () => {
  vi.useFakeTimers();
  await flushPromises();
});

test("no leak when handles are closed", async () => {
  await expectNoLeakedHandles(async () => {
    const t = setTimeout(() => {}, 10_000);
    clearTimeout(t);
    const server = createServer().listen(0);
    await new Promise<void>((res) => server.close(() => res()));
  });
});

test("reports leaked timers and servers", async () => {
  const existing = setTimeout(() => {}, 10_000); // open before: not a leak
  const server = createServer();
  let leakedTimer: ReturnType<typeof setTimeout> | undefined;
  try {
    await expect(
      expectNoLeakedHandles(
        async () => {
          leakedTimer = setTimeout(() => {}, 10_000);
          await new Promise<void>((res) => server.listen(0, res));
        },
        { timeoutMs: 20 },
      ),
    ).rejects.toThrow(
      /^Handles still open 20\.00ms after the body finished: (?=.*1 × Timeout)(?=.*TCPServerWrap)/,
    );
  } finally {
    clearTimeout(existing);
    clearTimeout(leakedTimer);
    server.close();
  }
});

test("validates options", async () => {
  await expect(expectNoLeakedHandles(() => {}, { timeoutMs: -1 })).rejects.toThrow(RangeError);
});
