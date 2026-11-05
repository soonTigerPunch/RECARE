import test from "node:test";
import assert from "node:assert/strict";
import { requestFixture, outputFixture } from "./validation.test.ts";
const mod = (await import(
  "../supabase/functions/recipe-recommendations/handler.ts"
).catch(() => ({}))) as any;
const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  sessionId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const token = (extra: any = {}) =>
  [
    "eyJhbGciOiJIUzI1NiJ9",
    btoa(
      JSON.stringify({
        sub: userId,
        session_id: sessionId,
        exp: Math.floor(Date.now() / 1000) + 3600,
        iat: Math.floor(Date.now() / 1000),
        is_anonymous: true,
        ...extra,
      }),
    ).replace(/=/g, ""),
    "fake-signature",
  ].join(".");
const config = () => ({
  enabled: true,
  policyApproved: true,
  supabaseUrl: "https://mock.supabase.co",
  publishableKey: "sb_publishable_fake",
  serviceRoleKey: "service-only-fake",
  encryptionKey: "11".repeat(32),
  pseudonymKey: "22".repeat(32),
  trustedIpHeader: "x-forwarded-for",
  openaiKey: "openai-only-fake",
  model: "gpt-4.1-mini",
  maxOutputTokens: 4000,
  inputPriceMicro: 400000,
  outputPriceMicro: 1600000,
});
function harness(opts: any = {}) {
  const calls: any[] = [];
  const jobs = new Map<string, any>();
  let generations = 0;
  const fetcher = async (url: any, init: any = {}) => {
    calls.push({ url, init });
    const body = init.body ? JSON.parse(init.body) : null;
    const json = (v: any, status = 200) =>
      new Response(JSON.stringify(v), { status });
    if (url.endsWith("/auth/v1/user"))
      return json(
        opts.user ?? {
          id: userId,
          is_anonymous: true,
          created_at: new Date(Date.now() - 86400000).toISOString(),
        },
        opts.authStatus ?? 200,
      );
    if (url.includes("/rest/v1/rpc/")) {
      assert.equal(init.headers.Authorization, "Bearer service-only-fake");
      const fn = url.split("/").at(-1);
      if (opts.rpcFail)
        return json({ message: "service-only-fake private database" }, 500);
      if (fn === "recipe_rate_gate")
        return json({ code: opts.rateLimited ? "rate_limited" : "ok" });
      const key = body.p_session_hash + "/" + body.p_request_id;
      const job = jobs.get(key);
      if (fn === "recipe_issue") {
        if (!job)
          jobs.set(key, {
            code: "issued",
            expires_at: new Date(Date.now() + 86400000).toISOString(),
          });
        return json({ ...jobs.get(key), request_id: body.p_request_id });
      }
      if (fn === "recipe_lookup") return json(job ?? { code: "not_found" });
      if (fn === "recipe_reserve") {
        if (opts.reserveCode) return json({ code: opts.reserveCode });
        if (!job) return json({ code: "not_found" });
        if (job.hash && job.hash !== body.p_request_hash)
          return json({ code: "conflict" });
        if (job.code !== "issued") return json(job);
        job.hash = body.p_request_hash;
        job.code = "in_progress";
        return json({ code: "reserved", reserved_micro: 70000 });
      }
      if (fn === "recipe_finish") {
        Object.assign(job, {
          code: body.p_success ? "complete" : body.p_error_code,
          ciphertext: body.p_ciphertext,
        });
        return json(job);
      }
      throw new Error("Unexpected RPC " + fn);
    }
    if (url === "https://api.openai.com/v1/responses") {
      generations++;
      if (opts.model) return opts.model();
      return json({
        status: "completed",
        output: [
          {
            type: "message",
            content: [
              { type: "output_text", text: JSON.stringify(outputFixture()) },
            ],
          },
        ],
        usage: { input_tokens: 100, output_tokens: 100 },
      });
    }
    throw new Error("Unexpected network " + url);
  };
  const handler = () => mod.createHandler(config(), fetcher);
  const request = (
    method = "POST",
    payload: any = requestFixture(),
    query = "",
  ) =>
    new Request(
      "https://mock.supabase.co/functions/v1/recipe-recommendations" + query,
      {
        method,
        headers: {
          apikey: "sb_publishable_fake",
          Authorization: "Bearer " + token(),
          "Content-Type": "application/json",
          "x-forwarded-for": "203.0.113.2",
        },
        ...(method === "GET" ? {} : { body: JSON.stringify(payload) }),
      },
    );
  return { calls, jobs, handler, request, generations: () => generations };
}
test("disabled-by-default endpoint cannot call any dependency", async () => {
  assert.equal(typeof mod.createHandler, "function");
  let calls = 0;
  const handler = mod.createHandler(
    mod.configFromEnv(() => undefined),
    async () => {
      calls++;
      throw new Error();
    },
  );
  const response = await handler(
    new Request("https://local/", { method: "POST" }),
  );
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error.code, "disabled");
  assert.equal(calls, 0);
});
test("an issued request generates once, stores ciphertext, and replays the identical response", async () => {
  const h = harness();
  let res = await h.handler()(
    h.request(
      "POST",
      { request_id: requestFixture().request_id },
      "?action=issue",
    ),
  );
  assert.equal(res.status, 200);
  res = await h.handler()(h.request());
  assert.equal(res.status, 200);
  const first = await res.json();
  assert.equal(first.recipes.length, 1);
  const replay = await h.handler()(h.request());
  assert.deepEqual(await replay.json(), first);
  assert.equal(h.generations(), 1);
  const finish = h.calls.find((c) => c.url.endsWith("recipe_finish"));
  assert.equal(finish.init.body.includes("두부"), false);
  assert.equal(finish.init.body.includes("exclusions"), false);
});
test("lookup is session bound and never creates or generates a job", async () => {
  const h = harness();
  const res = await h.handler()(
    h.request("GET", null, "?request_id=" + requestFixture().request_id),
  );
  assert.equal(res.status, 404);
  assert.equal((await res.json()).error.code, "not_found");
  assert.equal(h.generations(), 0);
  assert.equal(
    h.calls.some(
      (c) => c.url.endsWith("recipe_issue") || c.url.endsWith("recipe_reserve"),
    ),
    false,
  );
});
test("unissued and changed-payload requests do not generate", async () => {
  const h = harness();
  let r = await h.handler()(h.request());
  assert.equal(r.status, 404);
  await h.handler()(
    h.request(
      "POST",
      { request_id: requestFixture().request_id },
      "?action=issue",
    ),
  );
  await h.handler()(h.request());
  const req = requestFixture();
  req.servings = 2;
  r = await h.handler()(h.request("POST", req));
  assert.equal(r.status, 409);
  assert.equal((await r.json()).error.code, "conflict");
  assert.equal(h.generations(), 1);
});
test("quota, concurrent, expired and budget RPC rejections block every model call", async () => {
  for (const code of [
    "daily_limit",
    "budget_limit",
    "in_progress",
    "expired",
    "configuration",
  ]) {
    const h = harness({ reserveCode: code });
    const res = await h.handler()(h.request());
    assert.ok(res.status >= 400);
    assert.equal((await res.json()).error.code, code);
    assert.equal(h.generations(), 0);
  }
});
test("PostgREST errors fail closed and expose no service secret", async () => {
  const h = harness({ rpcFail: true });
  const res = await h.handler()(h.request());
  assert.equal(res.status, 503);
  const text = await res.text();
  assert.equal(text.includes("service-only-fake"), false);
  assert.equal(text.includes("database"), false);
  assert.equal(h.generations(), 0);
});
test("forged/expired/nonanonymous/over-30-day sessions are rejected before generation", async () => {
  for (const opts of [
    { authStatus: 401 },
    {
      user: {
        id: userId,
        is_anonymous: false,
        created_at: new Date().toISOString(),
      },
    },
    {
      user: {
        id: userId,
        is_anonymous: true,
        created_at: new Date(Date.now() - 31 * 86400000).toISOString(),
      },
    },
  ]) {
    const h = harness(opts);
    const res = await h.handler()(h.request());
    assert.equal(res.status, 401);
    assert.equal(h.generations(), 0);
  }
  const h = harness();
  const req = h.request();
  req.headers.set("Authorization", "Bearer " + token({ exp: 1 }));
  assert.equal((await h.handler()(req)).status, 401);
});
test("IP limiter covers invalid auth and oversize inputs, and missing trusted IP blocks activation", async () => {
  const h = harness({ rateLimited: true });
  const r = await h.handler()(h.request());
  assert.equal(r.status, 429);
  assert.equal(
    h.calls.some((c) => c.url.includes("/auth/")),
    false,
  );
  const missing = config();
  missing.trustedIpHeader = "";
  const res = await mod.createHandler(missing, async () => {
    throw new Error("must not fetch");
  })(h.request());
  assert.equal((await res.json()).error.code, "configuration");
});
test("ambiguous timeout is persisted and retry never starts a replacement generation", async () => {
  const h = harness({
    model: async () => {
      throw new TypeError("openai-only-fake");
    },
  });
  await h.handler()(
    h.request(
      "POST",
      { request_id: requestFixture().request_id },
      "?action=issue",
    ),
  );
  const res = await h.handler()(h.request());
  assert.equal(res.status, 504);
  const first = await res.json();
  const second = await h.handler()(h.request());
  assert.deepEqual(await second.json(), first);
  assert.equal(h.generations(), 1);
});
test("unsafe method, request shape and non-JSON content never trigger generation", async () => {
  const h = harness();
  const req = h.request("POST", { ...requestFixture(), food_ids: ["private"] });
  const r = await h.handler()(req);
  assert.equal(r.status, 400);
  assert.equal(h.generations(), 0);
  const wrong = h.request();
  wrong.headers.set("Content-Type", "text/plain");
  assert.equal((await h.handler()(wrong)).status, 400);
});
