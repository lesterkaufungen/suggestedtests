// Loads the Node-API addon built from native/node/ in the monorepo. Mirrors
// native/node/src/lib.rs; keep the two in sync.
//
// The addon is looked up, in order, at:
//  1. $SUGGESTEDTESTS_NATIVE_ADDON (an explicit path, e.g. a local cargo build),
//  2. prebuilds/<platform>/ of this package (installed from npm),
//  3. native/prebuilt/<platform>/ of the monorepo (development checkout).

import { closeSync, existsSync, openSync, readSync, readdirSync } from "fs";
import { join } from "path";

/** @internal */
export const ABI_VERSION = 1;
/** @internal */
export const ST_OK = 0;
/** @internal */
export const ST_ERR_NULL = -1;
/** @internal */
export const ST_ERR_UNSUPPORTED = -2;
/** @internal */
export const ST_ERR_UNKNOWN = -3;

/** @internal */
export const ENV_VAR = "SUGGESTEDTESTS_NATIVE_ADDON";
/** @internal Read by the bridge when it loads: turns its startup report on. */
export const VERBOSE_ENV_VAR = "SUGGESTEDTESTS_VERBOSE";

const ADDON = "suggestedtests_native.node";

/** @internal The functions exported by the addon. */
export interface Addon {
  abiVersion(): number;
  /** Additive (no ABI bump): absent from an addon built before this existed. */
  onLoad?(): number;
  processCpuTime(out: BigUint64Array): number;
  threadCpuTimeNs(out: BigUint64Array): number;
  memoryUsage(out: BigUint64Array): number;
  cpuCount(): number;
  setVerbose(verbose: number): number;
  verbose(): number;
}

/** @internal The program interpreter (`PT_INTERP`) of a little-endian ELF file (32 or 64-bit). */
export function elfInterpreter(path: string): string | undefined {
  let fd: number | undefined;
  try {
    fd = openSync(path, "r");
    const read = (length: number, position: number): Buffer => {
      const buffer = Buffer.alloc(length);
      const n = readSync(fd!, buffer, 0, length, position);
      return buffer.subarray(0, n);
    };
    const header = read(64, 0);
    if (
      header.length < 52 ||
      header.readUInt32BE(0) !== 0x7f454c46 || // \x7fELF
      (header[4] !== 1 && header[4] !== 2) || // 32- or 64-bit
      header[5] !== 1 // little-endian
    ) {
      return undefined;
    }
    const is64 = header[4] === 2;
    const phOffset = is64 ? Number(header.readBigUInt64LE(0x20)) : header.readUInt32LE(0x1c);
    const phSize = header.readUInt16LE(is64 ? 0x36 : 0x2a);
    const phCount = header.readUInt16LE(is64 ? 0x38 : 0x2c);
    for (let i = 0; i < phCount; i++) {
      const ph = read(phSize, phOffset + i * phSize);
      if (ph.length < 32 || ph.readUInt32LE(0) !== 3) continue; // PT_INTERP
      const offset = is64 ? Number(ph.readBigUInt64LE(8)) : ph.readUInt32LE(4);
      const size = is64 ? Number(ph.readBigUInt64LE(32)) : ph.readUInt32LE(16);
      const bytes = read(Math.min(size, 4096), offset);
      const end = bytes.indexOf(0);
      return bytes.subarray(0, end < 0 ? bytes.length : end).toString("latin1");
    }
    return undefined;
  } catch {
    return undefined;
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function usesMusl(): boolean {
  // A library built for one libc can't be loaded into a process using the
  // other, so ask the running node executable rather than the system.
  const interpreter = elfInterpreter(process.execPath);
  if (interpreter !== undefined) return interpreter.includes("musl");
  try {
    return readdirSync("/lib").some((name) => name.startsWith("ld-musl-"));
  } catch {
    return false;
  }
}

/** @internal `<os>-<arch>[-musl]`, the prebuilt directory for this process. */
export function platformDir(): string | undefined {
  const arch = (
    { x64: "x64", arm64: "arm64", ia32: "x86", arm: "arm", riscv64: "riscv64" } as Record<
      string,
      string
    >
  )[process.arch];
  if (arch === undefined) return undefined;
  switch (process.platform) {
    case "linux":
      return `linux-${arch}${usesMusl() ? "-musl" : ""}`;
    case "darwin":
      return `macos-${arch}`;
    case "win32":
      return `windows-${arch}`;
    default:
      return undefined;
  }
}

/** @internal Paths the addon is looked up at, in order. */
export function candidates(): string[] {
  const explicit = process.env[ENV_VAR];
  if (explicit) return [explicit];
  const dir = platformDir();
  if (dir === undefined) return [];
  // This file is <package>/src/native.ts or <package>/dist/native.js.
  const pkg = join(__dirname, "..");
  return [
    join(pkg, "prebuilds", dir, ADDON),
    join(pkg, "..", "..", "native", "prebuilt", dir, ADDON),
  ];
}

/** @internal Loads the addon. Throws if it is missing or incomplete. */
export function load(): Addon {
  const paths = candidates();
  if (paths.length === 0) {
    throw new Error(`no prebuilt addon for ${process.platform}/${process.arch}`);
  }
  const found = paths.find((p) => existsSync(p));
  if (found === undefined) {
    throw new Error(`addon not found at: ${paths.join(", ")}`);
  }
  const module = { exports: {} as Partial<Addon> };
  process.dlopen(module, found);
  if (typeof module.exports.abiVersion !== "function") {
    throw new Error(`${found} did not register (Node-API not found in this process)`);
  }
  return module.exports as Addon;
}
