import { spawnSync } from "child_process";
import { existsSync, mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { describe, expect, test } from "vitest";
import {
  CpuTime,
  formatBytes,
  formatMs,
  MemoryUsage,
  NativeBridgeError,
  SystemProbe,
} from "../src";
import * as native from "../src/native";

const burn = (): number => {
  let x = 0;
  for (let i = 0; i < 100_000; i++) x = (x * 31 + i) % 1_000_003;
  return x;
};

describe("formatting", () => {
  test("formatBytes", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(1536)).toBe("1.5 KiB");
    expect(formatBytes(5 * 1024 ** 2)).toBe("5.0 MiB");
    expect(formatBytes(-2048)).toBe("-2.0 KiB");
  });

  test("formatMs", () => {
    expect(formatMs(0.85)).toBe("850µs");
    expect(formatMs(1.25)).toBe("1.25ms");
    expect(formatMs(2000)).toBe("2.00s");
  });
});

test("CpuTime arithmetic", () => {
  const d = new CpuTime(30, 7).minus(new CpuTime(10, 2));
  expect([d.userNs, d.systemNs, d.totalNs]).toEqual([20, 5, 25]);
});

test("NativeBridgeError explains the code", () => {
  expect(new NativeBridgeError("x", native.ST_ERR_UNSUPPORTED).message).toContain(
    "not supported on this OS",
  );
  expect(new NativeBridgeError("x", 13).message).toContain("OS error 13");
});

describe("loader", () => {
  test("knows this platform", () => {
    expect(native.platformDir()).toBeDefined();
  });

  test("explicit path wins", () => {
    process.env[native.ENV_VAR] = "/nope/missing.node";
    try {
      expect(native.candidates()).toEqual(["/nope/missing.node"]);
      expect(() => native.load()).toThrow(/missing\.node/);
    } finally {
      delete process.env[native.ENV_VAR];
    }
  });

  test("elfInterpreter of a non-ELF file is undefined", () => {
    expect(native.elfInterpreter(__filename)).toBeUndefined();
  });
});

describe.skipIf(!SystemProbe.isAvailable)("with the native bridge", () => {
  test("is available", () => {
    expect(SystemProbe.skipReason).toBeUndefined();
  });

  test("process CPU time advances", () => {
    const before = SystemProbe.processCpuTime();
    while (SystemProbe.processCpuTime().minus(before).totalNs <= 0) burn();
  });

  test("thread CPU time advances", () => {
    const before = SystemProbe.threadCpuTimeNs();
    while (SystemProbe.threadCpuTimeNs() <= before) burn();
  });

  test("memory usage is plausible", () => {
    const m = SystemProbe.memoryUsage();
    expect(m).toBeInstanceOf(MemoryUsage);
    expect(m.currentRssBytes).toBeGreaterThan(1024 * 1024);
    expect(m.peakRssBytes).toBeGreaterThanOrEqual(m.currentRssBytes);
    expect(String(m)).toMatch(/MiB/);
  });

  test("cpu count", () => {
    expect(SystemProbe.cpuCount).toBeGreaterThanOrEqual(1);
  });

  test("addon rejects bad out-arrays", () => {
    const addon = native.load();
    expect(addon.processCpuTime(new BigUint64Array(1))).toBe(native.ST_ERR_NULL);
    expect(addon.memoryUsage(new Float64Array(2) as unknown as BigUint64Array)).toBe(
      native.ST_ERR_NULL,
    );
  });

  test("setVerbose rejects non-booleans", () => {
    expect(() => SystemProbe.setVerbose(1 as unknown as boolean)).toThrow(TypeError);
  });

  // The report goes to the process' stderr, so each case loads the addon in a
  // fresh Node process.
  const child = (code: string, env: Record<string, string> = {}) => {
    const path = native.candidates().find((p) => existsSync(p));
    const script =
      `const m = { exports: {} }; process.dlopen(m, ${JSON.stringify(path)});` +
      `const a = m.exports; ${code}`;
    const environ: Record<string, string | undefined> = { ...process.env, ...env };
    if (!(native.VERBOSE_ENV_VAR in env)) delete environ[native.VERBOSE_ENV_VAR];
    const r = spawnSync(process.execPath, ["-e", script], { env: environ, encoding: "utf8" });
    expect(r.status, r.stderr).toBe(0);
    return { out: r.stdout, err: r.stderr };
  };

  test("is silent by default", () => {
    const { out, err } = child("console.log(a.verbose())");
    expect(out.trim()).toBe("0");
    expect(err).not.toContain("suggestedtests:");
  });

  test("SUGGESTEDTESTS_VERBOSE prints the report when the addon loads", () => {
    const { out, err } = child("console.log(a.verbose())", { [native.VERBOSE_ENV_VAR]: "1" });
    expect(out.trim()).toBe("1");
    expect(err.split("suggestedtests: platform: ").length).toBe(2);
    expect(err).toContain("suggestedtests: environment: ");
  });

  test("setVerbose prints the report once", () => {
    const { out, err } = child(
      "console.log(a.setVerbose(1), a.setVerbose(1), a.setVerbose(0), a.verbose())",
    );
    expect(out.trim()).toBe("0 1 1 0");
    expect(err.split("suggestedtests: platform: ").length).toBe(2);
  });

  test("setVerbose and verbose round-trip", () => {
    const before = SystemProbe.verbose;
    expect(SystemProbe.setVerbose(before)).toBe(before);
    expect(SystemProbe.verbose).toBe(before);
  });
});

describe("elfInterpreter", () => {
  const elf = (cls: 1 | 2, interp: string): Buffer => {
    const is64 = cls === 2;
    const [ehsize, phsize] = is64 ? [64, 56] : [52, 32];
    const header = Buffer.alloc(ehsize);
    header.write("\x7fELF", 0, "latin1");
    header[4] = cls;
    header[5] = 1;
    const ph = Buffer.alloc(phsize);
    ph.writeUInt32LE(3, 0);
    const text = Buffer.from(interp + "\0", "latin1");
    if (is64) {
      header.writeBigUInt64LE(BigInt(ehsize), 0x20);
      header.writeUInt16LE(phsize, 0x36);
      header.writeUInt16LE(1, 0x38);
      ph.writeBigUInt64LE(BigInt(ehsize + phsize), 8);
      ph.writeBigUInt64LE(BigInt(text.length), 32);
    } else {
      header.writeUInt32LE(ehsize, 0x1c);
      header.writeUInt16LE(phsize, 0x2a);
      header.writeUInt16LE(1, 0x2c);
      ph.writeUInt32LE(ehsize + phsize, 4);
      ph.writeUInt32LE(text.length, 16);
    }
    return Buffer.concat([header, ph, text]);
  };

  test.each([
    [1, "/lib/ld-musl-armhf.so.1"],
    [2, "/lib64/ld-linux-x86-64.so.2"],
  ] as const)("reads ELF class %i", (cls, interp) => {
    const dir = mkdtempSync(join(tmpdir(), "st-elf-"));
    const file = join(dir, "bin");
    writeFileSync(file, elf(cls, interp));
    expect(native.elfInterpreter(file)).toBe(interp);
  });
});
