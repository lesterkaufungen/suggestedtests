// A tour of suggestedtests. Run it with: npx vitest run examples
import { createServer } from "node:net";
import { expect, test } from "vitest";
import {
  assertUnique,
  benchmarkSync,
  deferred,
  eventually,
  expectCompletesWithin,
  expectMemory,
  expectNoLeakedHandles,
  expectPerformance,
  flushPromises,
  matchers,
  MiB,
  scenario,
  SystemProbe,
  TestData,
} from "../src";

expect.extend(matchers);

class Cart {
  private items: number[] = [];
  add(price: number): this {
    this.items.push(price);
    return this;
  }
  get total(): number {
    return this.items.reduce((a, b) => a + b, 0);
  }
}

test(
  "adding items updates the total",
  scenario((s) => {
    let cart: Cart;
    s.given("an empty cart", () => {
      cart = new Cart();
    });
    s.when("two items are added", () => cart.add(10).add(20));
    s.then("the total is 30", () => expect(cart.total).toBe(30));
  }),
);

test("seeded data is reproducible and unique", () => {
  const data = new TestData(42);
  const ids = data.listOf(100, (d) => d.uuid());
  assertUnique(ids);
  expect(new TestData(42).uuid()).toBe(ids[0]);
});

test("parsing stays fast", async () => {
  const payload = JSON.stringify({ items: Array.from({ length: 1000 }, (_, i) => i) });
  const result = await expectPerformance(() => JSON.parse(payload), { budgetMs: 50 });
  console.log(String(result));
});

test.skipIf(!SystemProbe.isAvailable)("CPU time ignores noisy neighbours", () => {
  const result = benchmarkSync("sum", () => Array.from({ length: 10_000 }).length, {
    clock: "cpu",
  });
  expect(result.median).toBeGreaterThanOrEqual(0);
});

test.skipIf(!SystemProbe.isAvailable)("building rows stays under budget", async () => {
  await expectMemory(() => Array.from({ length: 1000 }, (_, i) => ({ id: i })), {
    maxPeakGrowth: 512 * MiB,
  });
});

test("controls when async work completes", async () => {
  const response = deferred<string>();
  let shown = "loading";
  void response.promise.then((name) => (shown = name));
  await flushPromises();
  expect(shown).toBe("loading");
  response.resolve("Ada");
  await eventually(() => expect(shown).toBe("Ada"));
});

test("server closes everything it opens", async () => {
  await expectNoLeakedHandles(async () => {
    const server = createServer();
    await new Promise<void>((res) => server.listen(0, res));
    await new Promise<void>((res) => server.close(() => res()));
  });
});

test("load answers quickly", async () => {
  const load = async (): Promise<string> => "ok";
  await expect(expectCompletesWithin(load(), 1000)).resolves.toBe("ok");
});
