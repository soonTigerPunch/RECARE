import test from "node:test";
import assert from "node:assert/strict";
const mod = (await import(
  "../supabase/functions/recipe-recommendations/crypto.ts"
).catch(() => ({}))) as any;
test("encryption is randomized, authenticated and session/request bound", async () => {
  assert.equal(typeof mod.encryptResult, "function");
  const key = "11".repeat(32),
    value = { status: "ok", recipes: [] };
  const a = await mod.encryptResult(value, key, "session/request");
  const b = await mod.encryptResult(value, key, "session/request");
  assert.notEqual(a, b);
  assert.deepEqual(await mod.decryptResult(a, key, "session/request"), value);
  assert.equal(a.includes("recipes"), false);
  await assert.rejects(() => mod.decryptResult(a, key, "other/request"));
  await assert.rejects(() =>
    mod.decryptResult(a, "22".repeat(32), "session/request"),
  );
});
test("canonical hash is independent of object key order but changes for changed constraints", async () => {
  assert.equal(
    await mod.requestHash({ b: 2, a: 1 }),
    await mod.requestHash({ a: 1, b: 2 }),
  );
  assert.notEqual(
    await mod.requestHash({ a: 1 }),
    await mod.requestHash({ a: 2 }),
  );
});
