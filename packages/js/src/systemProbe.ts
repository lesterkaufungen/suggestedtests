import * as native from "./native";

/** Formats a byte count as a human readable size, e.g. `12.5 MiB`. */
export function formatBytes(bytes: number): string {
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let value = Math.abs(bytes);
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  if (unit === 0) return `${bytes} B`;
  return `${bytes < 0 ? "-" : ""}${value.toFixed(1)} ${units[unit]}`;
}

/** Formats milliseconds as `850µs`, `1.25ms` or `2.00s`. */
export function formatMs(ms: number): string {
  if (Math.abs(ms) < 1) return `${Math.round(ms * 1000)}µs`;
  if (Math.abs(ms) < 1000) return `${ms.toFixed(2)}ms`;
  return `${(ms / 1000).toFixed(2)}s`;
}

/** CPU time consumed by the process, split into user and kernel time. */
export class CpuTime {
  /**
   * @param userNs Time spent running user-space code, in nanoseconds.
   * @param systemNs Time spent in the kernel on behalf of the process.
   */
  constructor(
    readonly userNs: number,
    readonly systemNs: number,
  ) {}

  /** `userNs + systemNs`. */
  get totalNs(): number {
    return this.userNs + this.systemNs;
  }

  /** The CPU time spent between `earlier` and this sample. */
  minus(earlier: CpuTime): CpuTime {
    return new CpuTime(this.userNs - earlier.userNs, this.systemNs - earlier.systemNs);
  }

  /** @returns e.g. `CpuTime(user: 1.25ms, system: 0µs)`. */
  toString(): string {
    return `CpuTime(user: ${formatMs(this.userNs / 1e6)}, system: ${formatMs(this.systemNs / 1e6)})`;
  }
}

/** Resident memory (RSS / working set) of the process, in bytes. */
export class MemoryUsage {
  /**
   * @param currentRssBytes Memory currently resident in RAM.
   * @param peakRssBytes Highest resident memory since the process started.
   */
  constructor(
    readonly currentRssBytes: number,
    readonly peakRssBytes: number,
  ) {}

  /** @returns e.g. `MemoryUsage(current: 40.1 MiB, peak: 52.3 MiB)`. */
  toString(): string {
    return `MemoryUsage(current: ${formatBytes(this.currentRssBytes)}, peak: ${formatBytes(this.peakRssBytes)})`;
  }
}

/** Thrown when the native bridge is missing or an OS call fails. */
export class NativeBridgeError extends Error {
  override readonly name = "NativeBridgeError";

  /**
   * @param operation The bridge function that failed.
   * @param code Negative for bridge errors, positive for the raw OS error code
   *   (`errno` on Linux/macOS, `GetLastError()` on Windows).
   * @param detail Extra context, if any.
   */
  constructor(
    readonly operation: string,
    readonly code: number,
    readonly detail?: string,
  ) {
    const reason =
      {
        [native.ST_ERR_NULL]: "null pointer",
        [native.ST_ERR_UNSUPPORTED]: "not supported on this OS",
        [native.ST_ERR_UNKNOWN]: "unknown OS error",
      }[code] ?? `OS error ${code}`;
    super(`${operation} failed: ${reason}${detail ? `\n${detail}` : ""}`);
  }
}

let addon: native.Addon | undefined;
let unavailable: string | undefined;
let probed = false;

function probe(): void {
  if (probed) return;
  probed = true;
  try {
    const loaded = native.load();
    const version = loaded.abiVersion();
    if (version !== native.ABI_VERSION) {
      unavailable =
        `suggestedtests native bridge has ABI v${version}, ` +
        `expected v${native.ABI_VERSION}. Rebuild it.`;
      return;
    }
    try {
      // Best-effort and additive (no ABI bump): an older addon that predates
      // this export must not make the whole bridge look unavailable over it.
      loaded.onLoad?.();
    } catch {
      // Ignored.
    }
    addon = loaded;
  } catch (e) {
    unavailable =
      `suggestedtests native bridge is not available for this platform ` +
      `(${(e as Error).message}). Set $${native.ENV_VAR} to an addon built from native/node.`;
  }
}

/** @internal Loads the bridge now; never throws (see `SystemProbe.skipReason`). */
export function preload(): void {
  probe();
}

function bridge(operation: string): native.Addon {
  probe();
  if (addon === undefined) {
    throw new NativeBridgeError(operation, native.ST_ERR_UNSUPPORTED, unavailable);
  }
  return addon;
}

function check(operation: string, status: number): void {
  if (status !== native.ST_OK) throw new NativeBridgeError(operation, status);
}

/**
 * Process metrics read through the OS-agnostic Rust bridge (Windows, Linux
 * and macOS). The addon ships prebuilt in the npm package.
 *
 * Check `isAvailable`, or skip tests where it isn't:
 *
 * ```ts
 * test.skipIf(!SystemProbe.isAvailable)("no leak", async () => { ... });
 * ```
 */
export const SystemProbe = {
  /** Whether the native bridge is loaded and has the expected ABI version. */
  get isAvailable(): boolean {
    probe();
    return addon !== undefined;
  },

  /** `undefined` when available; otherwise why not. */
  get skipReason(): string | undefined {
    probe();
    return addon === undefined ? unavailable : undefined;
  },

  /** CPU time used by the whole process (all threads) so far. */
  processCpuTime(): CpuTime {
    const out = new BigUint64Array(2);
    check("processCpuTime", bridge("processCpuTime").processCpuTime(out));
    return new CpuTime(Number(out[0]), Number(out[1]));
  },

  /**
   * CPU time used by the calling OS thread so far, in nanoseconds. Each
   * worker thread has its own clock; the main thread runs all JS of the
   * event loop.
   */
  threadCpuTimeNs(): number {
    const out = new BigUint64Array(1);
    check("threadCpuTimeNs", bridge("threadCpuTimeNs").threadCpuTimeNs(out));
    return Number(out[0]);
  },

  /** Current and peak resident memory of the process. */
  memoryUsage(): MemoryUsage {
    const out = new BigUint64Array(2);
    check("memoryUsage", bridge("memoryUsage").memoryUsage(out));
    return new MemoryUsage(Number(out[0]), Number(out[1]));
  },

  /** Number of logical CPUs available to the process. */
  get cpuCount(): number {
    return bridge("cpuCount").cpuCount();
  },

  /**
   * Turns the bridge's startup report on or off and returns the previous
   * setting.
   *
   * The report is three `suggestedtests: ...` lines on stderr describing the
   * platform and environment (OS, arch, libc, container, VM). It is printed
   * at most once per process; turning verbose on prints it now if it hasn't
   * been printed. Verbose controls nothing else. To get it while the bridge
   * loads, set `SUGGESTEDTESTS_VERBOSE=1` before the first `SystemProbe` call.
   *
   * ```ts
   * SystemProbe.setVerbose(true);
   * ```
   */
  setVerbose(verbose: boolean): boolean {
    if (typeof verbose !== "boolean") {
      throw new TypeError(`verbose must be a boolean, got ${typeof verbose}`);
    }
    return bridge("setVerbose").setVerbose(verbose ? 1 : 0) !== 0;
  },

  /** Whether the bridge's startup report is on (see `setVerbose`). */
  get verbose(): boolean {
    return bridge("verbose").verbose() !== 0;
  },
};
