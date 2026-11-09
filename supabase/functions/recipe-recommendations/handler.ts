import { RecipeError, safeError, errorBody } from "./errors.ts";
import {
  encryptResult,
  decryptResult,
  pseudonym,
  requestHash,
} from "./crypto.ts";
import { uuid, validateRequest } from "./validation.ts";
import { boundedText, generateRecipes, generateMenus, generateSelectedRecipe, maximumCost } from "./model.ts";
import type { Fetcher, ModelConfig } from "./model.ts";
import { JobStore } from "./store.ts";
export type ServerConfig = ModelConfig & {
  enabled: boolean;
  pilotMode?: boolean;
  policyApproved: boolean;
  supabaseUrl: string;
  publishableKey: string;
  serviceRoleKey: string;
  encryptionKey: string;
  pseudonymKey: string;
  trustedIpHeader: string;
};
export function configFromEnv(
  env: (name: string) => string | undefined,
): ServerConfig {
  return {
    enabled: env("RECIPE_ENABLED") === "true",
    pilotMode: env("RECIPE_PILOT_MODE") === "true",
    policyApproved: env("RECIPE_PUBLIC_POLICY_APPROVED") === "true",
    supabaseUrl: (env("SUPABASE_URL") ?? "").replace(/\/$/, ""),
    publishableKey: env("RECIPE_PUBLISHABLE_KEY") ?? "",
    serviceRoleKey: env("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    encryptionKey: env("RECIPE_ENCRYPTION_KEY") ?? "",
    pseudonymKey: env("RECIPE_PSEUDONYM_KEY") ?? "",
    trustedIpHeader: env("RECIPE_TRUSTED_IP_HEADER") ?? "",
    openaiKey: env("OPENAI_API_KEY") ?? env("RECARE_KEY") ?? "",
    model: env("RECIPE_MODEL") ?? "gpt-4.1-mini",
    maxOutputTokens: 4000,
    inputPriceMicro: Number(env("RECIPE_INPUT_PRICE_MICRO_PER_MILLION") ?? 0),
    outputPriceMicro: Number(env("RECIPE_OUTPUT_PRICE_MICRO_PER_MILLION") ?? 0),
  };
}
function checkConfig(config: ServerConfig) {
  let validUrl = false;
  try {
    const u = new URL(config.supabaseUrl);
    validUrl =
      !u.username &&
      !u.password &&
      !u.search &&
      !u.hash &&
      (u.pathname === "/" || u.pathname === "") &&
      (u.protocol === "https:" ||
        (u.protocol === "http:" &&
          ["localhost", "127.0.0.1", "kong"].includes(u.hostname)));
  } catch {
    /* Missing settings fail closed. */
  }
  if (
    !validUrl ||
    (!config.pilotMode && !config.policyApproved) ||
    !config.publishableKey ||
    !config.serviceRoleKey ||
    !config.openaiKey ||
    !/^[a-f0-9]{64}$/i.test(config.encryptionKey) ||
    !/^[a-f0-9]{64}$/i.test(config.pseudonymKey) ||
    (!config.pilotMode && !["x-forwarded-for", "x-real-ip", "cf-connecting-ip"].includes(
      config.trustedIpHeader,
    )) ||
    !Number.isSafeInteger(config.inputPriceMicro) ||
    config.inputPriceMicro < 1 ||
    !Number.isSafeInteger(config.outputPriceMicro) ||
    config.outputPriceMicro < 1 ||
    !/^[a-zA-Z0-9._-]{1,100}$/.test(config.model) ||
    config.maxOutputTokens !== 4000 ||
    !Number.isSafeInteger(maximumCost(config))
  )
    throw new RecipeError("configuration");
}
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
function throwCode(record: any): never {
  throw new RecipeError(
    record.code,
    typeof record.retry_at === "string" ? record.retry_at : undefined,
  );
}
async function authenticate(
  request: Request,
  config: ServerConfig,
  fetcher: Fetcher,
  deadline: number,
): Promise<{session: string; userHash: string}> {
  const authorization = request.headers.get("authorization") ?? "";
  if (
    request.headers.get("apikey") !== config.publishableKey ||
    authorization.length > 6000 ||
    !/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(
      authorization,
    )
  )
    throw new RecipeError("unauthorized");
  const controller = new AbortController();
  const duration = Math.min(5000, deadline - Date.now());
  if (duration <= 0) throw new RecipeError("timeout");
  const timer = setTimeout(() => controller.abort(), duration);
  try {
    let response: Response;
    try {
      response = await fetcher(config.supabaseUrl + "/auth/v1/user", {
        headers: {
          apikey: config.publishableKey,
          Authorization: authorization,
        },
        signal: controller.signal,
      });
    } catch {
      throw new RecipeError("unavailable");
    }
    if (response.status === 401 || response.status === 403)
      throw new RecipeError("unauthorized");
    if (!response.ok) throw new RecipeError("unavailable");
    let user: any;
    try {
      user = JSON.parse(await boundedText(response, 32768));
    } catch {
      throw new RecipeError("unavailable");
    }
    // /user has verified this exact access token. Only now inspect its signed
    // claims; merely decoding an unverified JWT is never authentication.
    let claims: any;
    try {
      const p = authorization
        .split(".")[1]
        .replace(/-/g, "+")
        .replace(/_/g, "/");
      claims = JSON.parse(atob(p.padEnd(Math.ceil(p.length / 4) * 4, "=")));
    } catch {
      throw new RecipeError("unauthorized");
    }
    const now = Date.now(),
      created = Date.parse(user.created_at);
    if (
      !uuid(user.id) ||
      claims.sub !== user.id ||
      !uuid(claims.session_id) ||
      user.is_anonymous !== true ||
      claims.is_anonymous !== true ||
      !Number.isFinite(created) ||
      created > now + 60000 ||
      now - created >= 30 * 86400000 ||
      !Number.isInteger(claims.exp) ||
      claims.exp * 1000 <= now ||
      !Number.isInteger(claims.iat) ||
      claims.iat * 1000 > now + 60000
    )
      throw new RecipeError("unauthorized");
    return {session: await pseudonym("session:" + user.id + ":" + claims.session_id, config.pseudonymKey), userHash: await pseudonym("pilot-user:" + user.id, config.pseudonymKey)};
  } finally {
    clearTimeout(timer);
  }
}
async function readJson(request: Request): Promise<any> {
  if (
    !/^application\/json(?:\s*;|$)/i.test(
      request.headers.get("content-type") ?? "",
    )
  )
    throw new RecipeError("invalid_request");
  try {
    return JSON.parse(
      await boundedText(
        new Response(request.body, { headers: request.headers }),
        16384,
      ),
    );
  } catch {
    throw new RecipeError("invalid_request");
  }
}
async function replay(
  record: any,
  config: ServerConfig,
  context: string,
): Promise<Response> {
  if (record.ciphertext && record.code !== "expired") {
    const saved = await decryptResult(
      record.ciphertext,
      config.encryptionKey,
      context,
    );
    if (
      !Number.isInteger(saved.http_status) ||
      saved.http_status < 200 ||
      saved.http_status > 599 ||
      !saved.body
    )
      throw new RecipeError("unavailable");
    return json(saved.body, saved.http_status);
  }
  throwCode(record.code === "issued" ? { code: "not_found" } : record);
}
export function createHandler(
  config: ServerConfig,
  fetcher: Fetcher = fetch,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    const start = Date.now(),
      deadline = start + 30000;
    try {
      if (!config.enabled) throw new RecipeError("disabled");
      checkConfig(config);
      if (!["GET", "POST"].includes(request.method))
        throw new RecipeError("invalid_request");
      const url = new URL(request.url);
      const isRegistration = config.pilotMode && request.method === "POST" && url.searchParams.get("action") === "registration";
      const isIssue =
        request.method === "POST" && url.searchParams.get("action") === "issue";
      if (
        [...url.searchParams.keys()].some((k) =>
          request.method === "GET"
            ? k !== "request_id"
            : !(isIssue || isRegistration) || k !== "action",
        )
      )
        throw new RecipeError("invalid_request");
      const ip = (config.pilotMode ? "" : (request.headers.get(config.trustedIpHeader) ?? ""))
        .split(",")[0]
        .trim();
      if (!config.pilotMode && (ip.length < 3 || ip.length > 64 || !/^[:a-fA-F0-9.]+$/.test(ip)))
        throw new RecipeError("configuration");
      const store = new JobStore(
        config.supabaseUrl,
        config.serviceRoleKey,
        fetcher,
        deadline,
      );
      let identity: {session: string; userHash: string};
      if (config.pilotMode) {
        identity = await authenticate(request, config, fetcher, deadline);
        if (isRegistration) {
          const rate = await store.rpc("recipe_rate_gate", {p_scope_hash: identity.userHash, p_limit: 10});
          if (rate.code !== "ok") throwCode(rate);
          return json({registration_id: identity.userHash});
        }
        const access = await store.rpc("recipe_pilot_access", {p_user_hash: identity.userHash});
        if (access.code !== "ok") throw new RecipeError("not_enrolled");
      } else {
        const rate = await store.rpc("recipe_rate_gate", {
          p_scope_hash: await pseudonym("ip:" + ip, config.pseudonymKey), p_limit: 60,
        });
        if (rate.code !== "ok") throwCode(rate);
        identity = await authenticate(request, config, fetcher, deadline);
      }
      const session = identity.session;
      if (config.pilotMode) {
        const rate = await store.rpc("recipe_rate_gate", {p_scope_hash: identity.userHash, p_limit: 30});
        if (rate.code !== "ok") throwCode(rate);
      }
      if (request.method === "GET") {
        const id = url.searchParams.get("request_id");
        if (!uuid(id)) throw new RecipeError("invalid_request");
        return await replay(
          await store.rpc("recipe_lookup", {
            p_session_hash: session,
            p_request_id: id.toLowerCase(),
          }),
          config,
          session + "/" + id.toLowerCase(),
        );
      }
      const body = await readJson(request);
      if (isIssue) {
        if (
          !body ||
          Array.isArray(body) ||
          Object.keys(body).length !== 1 ||
          !uuid(body.request_id)
        )
          throw new RecipeError("invalid_request");
        const record = await store.rpc("recipe_issue", {
          p_session_hash: session,
          p_request_id: body.request_id.toLowerCase(),
        });
        if (record.code !== "issued") throwCode(record);
        return json({
          request_id: record.request_id,
          expires_at: record.expires_at,
        });
      }
      const {stage, parent_request_id, menu_id, ...wire} = body ?? {};
      if (stage !== undefined && stage !== 'menus' && stage !== 'detail') throw new RecipeError('invalid_request');
      if (stage !== 'detail' && (parent_request_id !== undefined || menu_id !== undefined)) throw new RecipeError('invalid_request');
      const input = validateRequest(wire), lease = crypto.randomUUID(), context = session + '/' + input.request_id;
      const {request_id: ignoredId, ...conditions} = input;
      const menuInputHash = await requestHash(conditions);
      let selectedTitle: string | undefined;
      if (stage === 'detail') {
        if (!uuid(parent_request_id) || parent_request_id.toLowerCase() === input.request_id || typeof menu_id !== 'string' || !/^m[0-4]$/.test(menu_id)) throw new RecipeError('invalid_request');
        const parentId = parent_request_id.toLowerCase();
        const parent = await store.rpc('recipe_lookup',{p_session_hash:session,p_request_id:parentId});
        if (parent.code !== 'complete' || !parent.ciphertext) throwCode(parent.code === 'issued' ? {code:'not_found'} : parent);
        const saved = await decryptResult(parent.ciphertext,config.encryptionKey,session+'/'+parentId);
        if (saved.stage !== 'menus' || saved.http_status !== 200) throw new RecipeError('invalid_request');
        if (saved.menu_input_hash !== menuInputHash) throw new RecipeError('conflict');
        const menu = saved.body?.menus?.find((m:any)=>m.id === menu_id);
        if (!menu || typeof menu.title !== 'string') throw new RecipeError('invalid_request');
        selectedTitle = menu.title;
      }
      const boundInput = stage === undefined ? input : {...input, stage, ...(stage === 'detail' ? {parent_request_id:parent_request_id.toLowerCase(),menu_id}: {})};
      const record = await store.rpc("recipe_reserve", {
        p_session_hash: session,
        p_request_id: input.request_id,
        p_request_hash: await requestHash(boundInput),
        p_lease: lease,
        p_required_cost: maximumCost(config),
      });
      if (record.code !== "reserved")
        return await replay(record, config, context);
      let httpStatus = 200,
        result: any,
        success = false,
        cost: number | null = null,
        errorCode: string | null = null;
      try {
        const generated = stage === 'menus'
          ? await generateMenus(input,config,fetcher,deadline-1500)
          : stage === 'detail'
            ? await generateSelectedRecipe(input,selectedTitle!,config,fetcher,deadline-1500)
            : await generateRecipes(input,config,fetcher,deadline-1500);
        result = { ...generated.value, generated_at: new Date().toISOString(), ...(stage ? {generation: { ...((generated as any).usage ?? {}),cost_micro:generated.costMicro }} : {}) };
        cost = generated.costMicro;
        success = true;
      } catch (error) {
        const safe = safeError(error);
        httpStatus = safe.status;
        result = errorBody(safe);
        errorCode = safe.code;
      }
      // The database lease survives process termination. A failed persistence call
      // never starts another model call; later lookup recovers a terminal timeout.
      const ciphertext = await encryptResult(
        { http_status: httpStatus, body: result, stage: stage ?? "legacy", ...(stage === "menus" ? {menu_input_hash:menuInputHash} : {}) },
        config.encryptionKey,
        context,
      );
      const finished = await store.rpc("recipe_finish", {
        p_session_hash: session,
        p_request_id: input.request_id,
        p_lease: lease,
        p_success: success,
        p_ciphertext: ciphertext,
        p_cost_micro: cost,
        p_error_code: errorCode,
        p_model: config.model,
      });
      if (!finished.ciphertext || finished.ciphertext !== ciphertext)
        return await replay(finished, config, context);
      return json(result, httpStatus);
    } catch (error) {
      const safe = safeError(error);
      return json(errorBody(safe), safe.status);
    }
  };
}
