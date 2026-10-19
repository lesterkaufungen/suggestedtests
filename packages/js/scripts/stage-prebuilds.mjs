// Copies every platform's Node addon from the monorepo's native/prebuilt/
// into prebuilds/<platform>/ so `npm pack` / `npm publish` ship them.
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const source = join(root, "..", "..", "native", "prebuilt");
const target = join(root, "prebuilds");
const addon = "suggestedtests_native.node";

if (!existsSync(source)) {
  if (existsSync(target)) process.exit(0); // packing outside the monorepo
  throw new Error(`no prebuilt addons at ${source}`);
}
rmSync(target, { recursive: true, force: true });
let count = 0;
for (const platform of readdirSync(source)) {
  const file = join(source, platform, addon);
  if (!existsSync(file)) continue;
  mkdirSync(join(target, platform), { recursive: true });
  cpSync(file, join(target, platform, addon));
  count++;
}
if (count === 0) throw new Error(`no ${addon} found under ${source}`);
console.log(`staged ${count} prebuilt addons into prebuilds/`);
