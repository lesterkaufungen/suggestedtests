// Runtime smoke test of the compiled package (dist/) without a test runner,
// for Node versions that Vitest and Jest no longer support (down to 10.20):
//
//   npm run build && node test-compat/smoke.js
//
// Plain CommonJS and ES2018 on purpose; "assert", not "node:assert".
"use strict";
const assert = require("assert");
const net = require("net");
const st = require("../dist/index.js");

const results = [];
async function check(name, fn) {
  try {
    await fn();
    results.push(["ok", name]);
  } catch (error) {
    results.push(["FAIL", name, error]);
  }
}

async function main() {
  await check("native bridge loads", () => {
    assert.strictEqual(st.SystemProbe.isAvailable, true, st.SystemProbe.skipReason);
    assert.ok(st.SystemProbe.memoryUsage().currentRssBytes > 1 << 20);
    assert.ok(st.SystemProbe.processCpuTime().totalNs > 0);
    assert.ok(st.SystemProbe.threadCpuTimeNs() > 0);
    assert.ok(st.SystemProbe.cpuCount >= 1);
  });
  await check("importing the package loads the bridge (startup report)", () => {
    const env = Object.assign({}, process.env, { SUGGESTEDTESTS_VERBOSE: "1" });
    const index = require.resolve("../dist/index.js");
    const r = require("child_process").spawnSync(
      process.execPath,
      ["-e", `require(${JSON.stringify(index)})`],
      {
        env,
        encoding: "utf8",
      },
    );
    assert.strictEqual(r.status, 0, r.stderr);
    assert.strictEqual(r.stderr.split("suggestedtests: platform: ").length, 2, r.stderr);
  });

  await check("benchmark and budgets", async () => {
    const r = await st.benchmark("b", () => {}, { iterations: 5, warmup: 1 });
    assert.strictEqual(r.samples.length, 5);
    assert.ok(/^b: n=5 min=/.test(String(r)));
    st.expectPerformanceSync(() => {}, { budgetMs: 1000 });
    assert.throws(
      () =>
        st.expectPerformanceSync(() => JSON.stringify(new Array(1e4).fill(1)), {
          budgetMs: 0,
          statistic: "max",
        }),
      /budget exceeded/,
    );
    const cpu = st.benchmarkSync("cpu", () => {}, { clock: "cpu", iterations: 3 });
    assert.strictEqual(cpu.clock, "cpu");
  });
  await check("memory budget", async () => {
    let keep;
    await assert.rejects(
      st.expectMemory(
        () => {
          keep = Buffer.alloc(64 << 20, 1);
        },
        { maxPeakGrowth: 0 },
      ),
      /peak RSS grew/,
    );
    assert.ok(keep.length > 0);
  });
  await check("eventually and expectCompletesWithin", async () => {
    let n = 0;
    assert.strictEqual(
      await st.eventually(
        () => {
          if (++n < 3) throw new Error("no");
          return n;
        },
        { intervalMs: 1 },
      ),
      3,
    );
    await assert.rejects(
      st.eventually(
        () => {
          throw new Error("boom");
        },
        { timeoutMs: 20 },
      ),
      (e) => /boom/.test(e.message) && e.cause instanceof Error,
    );
    await assert.rejects(
      st.expectCompletesWithin(new Promise(() => {}), 10),
      /did not complete within/,
    );
  });
  await check("scenario", async () => {
    await st.scenario((s) => {
      s.given("a", () => {});
      s.then("b", () => {});
    })();
    const error = await st
      .scenario((s) => {
        s.then("the total is 30", () => assert.strictEqual(20, 30));
      })()
      .catch((e) => e);
    assert.ok(error instanceof st.ScenarioStepFailure);
    assert.ok(/^Then: the total is 30/.test(error.message));
    assert.ok(error.cause instanceof Error);
  });
  await check("TestData is deterministic", () => {
    assert.strictEqual(new st.TestData(42).uuid(), new st.TestData(42).uuid());
    assert.ok(/@example\.com$/.test(new st.TestData(1).email()));
  });
  await check("assertUnique and matchers", () => {
    st.assertUnique([1, 2, 3]);
    assert.throws(() => st.assertUnique(["a", "b", "a"]), /appears at index 0 and 2/);
    assert.strictEqual(st.matchers.toHaveUniqueElements([1, 1]).pass, false);
  });
  await check("deferred, flushPromises and leaked handles", async () => {
    const d = st.deferred();
    d.resolve(1);
    assert.strictEqual(await d.promise, 1);
    await st.flushPromises();
    await st.expectNoLeakedHandles(async () => {
      const server = net.createServer();
      await new Promise((res) => server.listen(0, "127.0.0.1", res));
      await new Promise((res) => server.close(res));
    });
    let timer;
    await assert.rejects(
      st.expectNoLeakedHandles(
        () => {
          timer = setTimeout(() => {}, 10000);
        },
        { timeoutMs: 20 },
      ),
      /Handles still open/,
    );
    clearTimeout(timer);
  });

  for (const [status, name, error] of results) {
    console.log(`${status} ${name}${error ? `: ${error.stack || error}` : ""}`);
  }
  const failed = results.filter((r) => r[0] !== "ok").length;
  console.log(`node ${process.version}: ${results.length - failed}/${results.length} passed`);
  process.exitCode = failed ? 1 : 0;
}

main();
