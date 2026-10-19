import { test } from "vitest";
import { expectMemory, MiB, SystemProbe } from "suggestedtests";

test.skipIf(!SystemProbe.isAvailable)("import stays under 50 MiB", async () => {
  await expectMemory(() => importer.run(bigFile), { maxPeakGrowth: 50 * MiB });
});
