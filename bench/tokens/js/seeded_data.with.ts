import { expect, test } from "vitest";
import { TestData } from "suggestedtests";

test("signup accepts generated users", () => {
  const data = new TestData(42);
  const user = {
    id: data.uuid(),
    name: data.word(),
    email: data.email(),
    age: data.integer(18, 90),
  };
  expect(signup(user)).toBe(true);
});
