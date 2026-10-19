import { expect, test } from "vitest";

test("import stays under 50 MiB", async () => {
  const before = process.resourceUsage().maxRSS;
  await importer.run(bigFile);
  const growthKiB = process.resourceUsage().maxRSS - before;
  expect(
    growthKiB,
    `peak RSS grew by ${(growthKiB / 1024).toFixed(1)} MiB > 50 MiB`,
  ).toBeLessThanOrEqual(50 * 1024);
});
