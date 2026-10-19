// Loads a prebuilt Node addon and calls every export. Used by CI to prove the
// musl addon loads on Alpine.
//
//   node tool/check_load_node.js native/prebuilt/linux-x64-musl/suggestedtests_native.node
"use strict";
const assert = require("assert");
const path = require("path");

const module_ = { exports: {} };
process.dlopen(module_, path.resolve(process.argv[2]));
const addon = module_.exports;
const pair = new BigUint64Array(2);
const one = new BigUint64Array(1);

assert.strictEqual(addon.abiVersion(), 1, "unexpected ABI version");
assert.ok(addon.cpuCount() >= 1);
assert.strictEqual(addon.processCpuTime(pair), 0);
assert.strictEqual(addon.threadCpuTimeNs(one), 0);
assert.strictEqual(addon.memoryUsage(pair), 0);
assert.ok(pair[0] > 0n && pair[1] >= pair[0]);
assert.strictEqual(addon.memoryUsage(one), -1, "short array must be rejected");
console.log("OK", process.argv[2], `rss=${pair[0]} cpus=${addon.cpuCount()}`);
