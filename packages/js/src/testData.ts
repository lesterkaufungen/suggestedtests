const LOWER = "abcdefghijklmnopqrstuvwxyz";
/** The default alphabet of {@link TestData.string}. */
export const ALPHANUMERIC = LOWER + LOWER.toUpperCase() + "0123456789";
const WORDS = [
  "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india",
  "juliet", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo",
  "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu",
]; // prettier-ignore

/** splitmix32: expands a seed into well-mixed state words. */
function splitmix32(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x9e3779b9) >>> 0;
    let z = s;
    z = Math.imul(z ^ (z >>> 16), 0x85ebca6b);
    z = Math.imul(z ^ (z >>> 13), 0xc2b2ae35);
    return (z ^ (z >>> 16)) >>> 0;
  };
}

/**
 * Seeded random test data (xoshiro128** generator).
 *
 * The same seed always produces the same values, so a failing test can be
 * reproduced exactly. Log `seed` when using a random one.
 *
 * ```ts
 * const data = new TestData(42);
 * const user = { name: data.word(), email: data.email(), age: data.integer(18, 90) };
 * ```
 */
export class TestData {
  private readonly s: Uint32Array;

  /** @param seed Any integer; defaults to 0. */
  constructor(readonly seed: number = 0) {
    if (!Number.isSafeInteger(seed))
      throw new RangeError(`seed must be a safe integer, got ${seed}`);
    const mix = splitmix32(seed ^ Math.floor(seed / 2 ** 32));
    this.s = Uint32Array.of(mix(), mix(), mix(), mix());
  }

  /** A generator with a random seed. Read `seed` to reproduce it. */
  static randomSeed(): TestData {
    return new TestData(Math.floor(Math.random() * 2 ** 31));
  }

  /** The next 32 random bits. */
  private next(): number {
    const s = this.s;
    const result = Math.imul(rotl(Math.imul(s[1]!, 5), 7), 9) >>> 0;
    const t = s[1]! << 9;
    s[2]! ^= s[0]!;
    s[3]! ^= s[1]!;
    s[1]! ^= s[2]!;
    s[0]! ^= s[3]!;
    s[2]! ^= t;
    s[3] = rotl(s[3]!, 11);
    return result;
  }

  /** A float in `[0, 1)` with 53 random bits. */
  private float(): number {
    return ((this.next() >>> 5) * 2 ** 26 + (this.next() >>> 6)) / 2 ** 53;
  }

  /** An integer in `[min, max]` (inclusive). */
  integer(min = 0, max = 100): number {
    if (!Number.isSafeInteger(min) || !Number.isSafeInteger(max)) {
      throw new RangeError("min and max must be safe integers");
    }
    if (max < min) throw new RangeError(`max (${max}) < min (${min})`);
    return min + Math.floor(this.float() * (max - min + 1));
  }

  /** A float in `[min, max)`. */
  decimal(min = 0, max = 1): number {
    if (max < min) throw new RangeError(`max (${max}) < min (${min})`);
    return min + this.float() * (max - min);
  }

  /** `true` with the given probability. */
  boolean(probability = 0.5): boolean {
    if (!(probability >= 0 && probability <= 1)) {
      throw new RangeError(`probability must be in [0, 1], got ${probability}`);
    }
    return this.float() < probability;
  }

  /** A string of `length` characters drawn from `alphabet`. */
  string(length = 10, alphabet = ALPHANUMERIC): string {
    if (!Number.isInteger(length) || length < 0) {
      throw new RangeError(`length must be an integer >= 0, got ${length}`);
    }
    const chars = [...alphabet];
    if (chars.length === 0) throw new RangeError("alphabet must not be empty");
    return Array.from({ length }, () => chars[this.integer(0, chars.length - 1)]).join("");
  }

  /** A short lowercase word. */
  word(): string {
    return this.pick(WORDS);
  }

  /** A sentence of `words` words, capitalised and ending with a period. */
  sentence(words = 6): string {
    if (!Number.isInteger(words) || words < 1) {
      throw new RangeError(`words must be an integer >= 1, got ${words}`);
    }
    const s = Array.from({ length: words }, () => this.word()).join(" ");
    return `${s[0]!.toUpperCase()}${s.slice(1)}.`;
  }

  /** A syntactically valid address on the reserved `example.com` domain. */
  email(): string {
    return `${this.word()}.${this.string(5, LOWER)}@example.com`;
  }

  /** A version 4 UUID string. */
  uuid(): string {
    const b = Array.from({ length: 16 }, () => this.next() & 0xff);
    b[6] = (b[6]! & 0x0f) | 0x40;
    b[8] = (b[8]! & 0x3f) | 0x80;
    const hex = b.map((x) => x.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  /** A `Date` in `[from, to]` (default 2000-01-01 to 2030-01-01 UTC). */
  date(from = new Date(Date.UTC(2000, 0, 1)), to = new Date(Date.UTC(2030, 0, 1))): Date {
    if (to < from) throw new RangeError("to is before from");
    return new Date(from.getTime() + Math.floor(this.float() * (to.getTime() - from.getTime())));
  }

  /** A random element of `options`. */
  pick<T>(options: readonly T[]): T {
    if (options.length === 0) throw new RangeError("options must not be empty");
    return options[this.integer(0, options.length - 1)]!;
  }

  /** `count` values produced by `generate`. */
  listOf<T>(count: number, generate: (data: TestData) => T): T[] {
    if (!Number.isInteger(count) || count < 0) {
      throw new RangeError(`count must be an integer >= 0, got ${count}`);
    }
    return Array.from({ length: count }, () => generate(this));
  }

  /** A shuffled copy of `items` (Fisher–Yates). */
  shuffled<T>(items: Iterable<T>): T[] {
    const result = [...items];
    for (let i = result.length - 1; i > 0; i--) {
      const j = this.integer(0, i);
      [result[i], result[j]] = [result[j]!, result[i]!];
    }
    return result;
  }
}

function rotl(x: number, k: number): number {
  return ((x << k) | (x >>> (32 - k))) >>> 0;
}
