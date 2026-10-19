import { expect, test } from "vitest";
import { TestData } from "../src";

test("same seed, same values", () => {
  const a = new TestData(42);
  const b = new TestData(42);
  expect(Array.from({ length: 5 }, () => a.integer())).toEqual(
    Array.from({ length: 5 }, () => b.integer()),
  );
  expect(a.uuid()).toBe(b.uuid());
  expect(new TestData(1).integer(0, 1e9)).not.toBe(new TestData(2).integer(0, 1e9));
});

test("values stay in range and cover it", () => {
  const d = new TestData(7);
  const seen = new Set<number>();
  for (let i = 0; i < 500; i++) {
    const n = d.integer(3, 5);
    expect(n).toBeGreaterThanOrEqual(3);
    expect(n).toBeLessThanOrEqual(5);
    seen.add(n);
    const f = d.decimal(1, 2);
    expect(f >= 1 && f < 2).toBe(true);
  }
  expect([...seen].sort()).toEqual([3, 4, 5]);
  expect(d.integer(7, 7)).toBe(7);
});

test("strings", () => {
  const d = new TestData(3);
  expect(d.string(12)).toHaveLength(12);
  expect(d.string(50, "ab")).toMatch(/^[ab]{50}$/);
  expect(d.sentence()).toMatch(/^[A-Z][a-z]+( [a-z]+){5}\.$/);
  expect(d.email()).toMatch(/^[a-z]+\.[a-z]{5}@example\.com$/);
  expect(d.uuid()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test("dates and collections", () => {
  const d = new TestData(4);
  const from = new Date("2020-01-01T00:00:00Z");
  const to = new Date("2020-02-01T00:00:00Z");
  const date = d.date(from, to);
  expect(date >= from && date <= to).toBe(true);
  expect([1, 2, 3]).toContain(d.pick([1, 2, 3]));
  expect(d.listOf(3, (g) => g.word())).toHaveLength(3);
  expect(d.shuffled([1, 2, 3, 4, 5]).sort()).toEqual([1, 2, 3, 4, 5]);
});

test.each([
  ["integer", (d: TestData) => d.integer(5, 1)],
  ["decimal", (d: TestData) => d.decimal(2, 1)],
  ["boolean", (d: TestData) => d.boolean(2)],
  ["string length", (d: TestData) => d.string(-1)],
  ["empty alphabet", (d: TestData) => d.string(3, "")],
  ["sentence", (d: TestData) => d.sentence(0)],
  ["pick", (d: TestData) => d.pick([])],
  ["listOf", (d: TestData) => d.listOf(-1, () => 1)],
  ["date", (d: TestData) => d.date(new Date(2021, 0), new Date(2020, 0))],
  ["seed", () => new TestData(1.5)],
])("rejects bad %s", (_, call) => {
  expect(() => call(new TestData())).toThrow(RangeError);
});

test("randomSeed is reproducible", () => {
  const d = TestData.randomSeed();
  expect(new TestData(d.seed).integer()).toBe(d.integer());
});
