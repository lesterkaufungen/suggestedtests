import { expect, test } from "vitest";

const countResources = () =>
  process.getActiveResourcesInfo().reduce<Record<string, number>>((counts, type) => {
    counts[type] = (counts[type] ?? 0) + 1;
    return counts;
  }, {});

test("server shuts down cleanly", async () => {
  const before = countResources();
  const server = await startServer();
  await server.close();
  await new Promise((resolve) => setTimeout(resolve, 100));
  const after = countResources();
  const leaked = Object.keys(after)
    .filter((type) => after[type] > (before[type] ?? 0))
    .map((type) => `${after[type] - (before[type] ?? 0)} × ${type}`);
  expect(leaked, `handles still open after the body finished: ${leaked.join(", ")}`).toEqual([]);
});
