import test from "node:test";
import assert from "node:assert/strict";
import { requestFixture, outputFixture } from "./validation.test.ts";
const mod = (await import(
  "../supabase/functions/recipe-recommendations/model.ts"
).catch(() => ({}))) as any;
const config = {
  openaiKey: "fake-never-network",
  model: "gpt-4.1-mini",
  maxOutputTokens: 4000,
  inputPriceMicro: 400000,
  outputPriceMicro: 1600000,
};
const response = (value: any) =>
  new Response(
    JSON.stringify({
      status: "completed",
      output: [
        {
          type: "message",
          content: [{ type: "output_text", text: JSON.stringify(value) }],
        },
      ],
      usage: { input_tokens: 200, output_tokens: 100 },
    }),
    { status: 200 },
  );
test("model sends only structured fixed request with store false and no local/request identity", async () => {
  assert.equal(typeof mod.generateRecipes, "function");
  let calls = 0;
  const result = await mod.generateRecipes(
    requestFixture(),
    config,
    async (url: any, init: any) => {
      calls++;
      assert.equal(url, "https://api.openai.com/v1/responses");
      const body = JSON.parse(init.body);
      assert.equal(body.store, false);
      assert.equal(body.model, "gpt-4.1-mini");
      assert.equal(body.text.format.strict, true);
      assert.equal(body.tools, undefined);
      assert.equal(init.body.includes(requestFixture().request_id), false);
      return response(outputFixture());
    },
    Date.now() + 30000,
  );
  assert.equal(result.value.recipes.length, 1);
  assert.equal(calls, 1);
  assert.ok(result.costMicro > 0);
});
test("all invalid candidates get one correction and partial-valid results get none", async () => {
  let calls = 0;
  const bad = outputFixture();
  bad.recipes[0].ingredients[0].amount = 900000;
  const result = await mod.generateRecipes(
    requestFixture(),
    config,
    async () => response(++calls === 1 ? bad : outputFixture()),
    Date.now() + 30000,
  );
  assert.equal(calls, 2);
  assert.equal(result.value.recipes.length, 1);
  calls = 0;
  const mixed = outputFixture();
  mixed.recipes.push(bad.recipes[0]);
  await mod.generateRecipes(
    requestFixture(),
    config,
    async () => {
      calls++;
      return response(mixed);
    },
    Date.now() + 30000,
  );
  assert.equal(calls, 1);
});
test("ambiguous network failures, refusals, incomplete and provider auth errors never retry", async () => {
  for (const fn of [
    async () => {
      throw new TypeError("network secret");
    },
    async () =>
      new Response(JSON.stringify({ status: "incomplete", output: [] }), {
        status: 200,
      }),
    async () =>
      new Response(
        JSON.stringify({
          status: "completed",
          output: [
            { type: "message", content: [{ type: "refusal", refusal: "no" }] },
          ],
        }),
        { status: 200 },
      ),
    async () => new Response("private provider body", { status: 401 }),
  ]) {
    let calls = 0;
    await assert.rejects(
      () =>
        mod.generateRecipes(
          requestFixture(),
          config,
          async () => {
            calls++;
            return fn();
          },
          Date.now() + 30000,
        ),
      (error: any) => {
        assert.equal(error.message.includes("secret"), false);
        assert.equal(error.message.includes("private"), false);
        return true;
      },
    );
    assert.equal(calls, 1);
  }
});
test("provider rate and budget errors are safely distinguished", async () => {
  for (const [body, code] of [
    [{ error: { code: "insufficient_quota" } }, "configuration"],
    [{ error: { code: "rate_limit_exceeded" } }, "rate_limited"],
  ])
    await assert.rejects(
      () =>
        mod.generateRecipes(
          requestFixture(),
          config,
          async () => new Response(JSON.stringify(body), { status: 429 }),
          Date.now() + 30000,
        ),
      (error: any) => error.code === code,
    );
});
test("malformed completed output still charges both attempts when correction succeeds", async () => {
  let calls = 0;
  const malformed = new Response(
    JSON.stringify({
      status: "completed",
      output: [
        {
          type: "message",
          content: [{ type: "output_text", text: "{not valid JSON" }],
        },
      ],
      usage: { input_tokens: 200, output_tokens: 100 },
    }),
  );
  const result = await mod.generateRecipes(
    requestFixture(),
    config,
    async () => (++calls === 1 ? malformed : response(outputFixture())),
    Date.now() + 30000,
  );
  assert.equal(calls, 2);
  assert.equal(result.costMicro, 480);
});
test("unreadable provider JSON conservatively retains full reservation after correction", async () => {
  let calls = 0;
  const result = await mod.generateRecipes(
    requestFixture(),
    config,
    async () =>
      ++calls === 1 ? new Response("not JSON") : response(outputFixture()),
    Date.now() + 30000,
  );
  assert.equal(calls, 2);
  assert.equal(result.costMicro, null);
});
test("provider model-access and invalid-model errors are nonretryable configuration failures", async () => {
  for (const [status, error] of [
    [404, { code: "model_not_found", message: "private model detail" }],
    [
      400,
      {
        code: "invalid_request_error",
        param: "model",
        message: "private model detail",
      },
    ],
  ]) {
    let calls = 0;
    await assert.rejects(
      () =>
        mod.generateRecipes(
          requestFixture(),
          config,
          async () => {
            calls++;
            return new Response(JSON.stringify({ error }), {
              status: status as number,
            });
          },
          Date.now() + 30000,
        ),
      (e: any) =>
        e.code === "configuration" &&
        e.retryable === false &&
        !e.message.includes("private"),
    );
    assert.equal(calls, 1);
  }
});
