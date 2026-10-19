import { performance } from "perf_hooks";
import { expect, test } from "vitest";

test("parsing stays fast", () => {
  for (let i = 0; i < 3; i++) parse(bigJson);
  const samples: number[] = [];
  for (let i = 0; i < 20; i++) {
    const start = performance.now();
    parse(bigJson);
    samples.push(performance.now() - start);
  }
  samples.sort((a, b) => a - b);
  const median = (samples[9] + samples[10]) / 2;
  expect(
    median,
    `parse: median ${median.toFixed(2)}ms > budget 5ms (min ${samples[0].toFixed(2)}ms, max ${samples[19].toFixed(2)}ms)`,
  ).toBeLessThanOrEqual(5);
});
