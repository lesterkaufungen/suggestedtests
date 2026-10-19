import { expect, test } from "vitest";

// Math.random() can't be seeded, so a reproducible test needs its own PRNG.
function mulberry32(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

test("signup accepts generated users", () => {
  const random = mulberry32(42);
  const int = (min: number, max: number) => min + Math.floor(random() * (max - min + 1));
  const word = () =>
    Array.from({ length: int(4, 8) }, () => String.fromCharCode(97 + int(0, 25))).join("");
  const hex = (n: number) => Array.from({ length: n }, () => int(0, 15).toString(16)).join("");
  const id = `${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + int(0, 3)).toString(16)}${hex(3)}-${hex(12)}`;
  const user = { id, name: word(), email: `${word()}.${word()}@example.com`, age: int(18, 90) };
  expect(signup(user)).toBe(true);
});
