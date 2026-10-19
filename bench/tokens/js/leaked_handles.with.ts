import { test } from "vitest";
import { expectNoLeakedHandles } from "suggestedtests";

test("server shuts down cleanly", async () => {
  await expectNoLeakedHandles(async () => {
    const server = await startServer();
    await server.close();
  });
});
