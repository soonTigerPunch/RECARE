import { RecipeError } from "./errors.ts";
const encoder = new TextEncoder(),
  decoder = new TextDecoder();
function bytes(key: string) {
  if (!/^[a-f0-9]{64}$/i.test(key)) throw new RecipeError("configuration");
  return Uint8Array.from(key.match(/../g)!, (x) => parseInt(x, 16));
}
function encode(value: Uint8Array) {
  let result = "";
  for (const c of value) result += String.fromCharCode(c);
  return btoa(result);
}
function decode(value: string) {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}
async function aes(key: string) {
  return crypto.subtle.importKey("raw", bytes(key), "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}
export async function encryptResult(
  value: unknown,
  key: string,
  context: string,
): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: encoder.encode(context) },
    await aes(key),
    encoder.encode(JSON.stringify(value)),
  );
  return "v1." + encode(iv) + "." + encode(new Uint8Array(data));
}
export async function decryptResult(
  value: string,
  key: string,
  context: string,
): Promise<any> {
  try {
    const [version, iv, data] = value.split(".");
    if (version !== "v1" || !iv || !data) throw new Error();
    const plain = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: decode(iv),
        additionalData: encoder.encode(context),
      },
      await aes(key),
      decode(data),
    );
    return JSON.parse(decoder.decode(plain));
  } catch {
    throw new RecipeError("unavailable");
  }
}
function canonical(value: any): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  return (
    "{" +
    Object.keys(value)
      .sort()
      .map((k) => JSON.stringify(k) + ":" + canonical(value[k]))
      .join(",") +
    "}"
  );
}
export async function requestHash(value: unknown): Promise<string> {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", encoder.encode(canonical(value))),
    ),
  )
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
export async function pseudonym(value: string, key: string): Promise<string> {
  const secret = await crypto.subtle.importKey(
    "raw",
    bytes(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return Array.from(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", secret, encoder.encode(value)),
    ),
  )
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
