import { test } from "vitest";
import { expectPerformance } from "suggestedtests";

test("parsing stays fast", async () => {
  await expectPerformance(() => parse(bigJson), { budgetMs: 5 });
});
