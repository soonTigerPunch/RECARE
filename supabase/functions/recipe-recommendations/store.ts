import { RecipeError } from "./errors.ts";
import { boundedText } from "./model.ts";
import type { Fetcher } from "./model.ts";
export class JobStore {
  url: string;
  key: string;
  fetcher: Fetcher;
  deadline: number;
  constructor(url: string, key: string, fetcher: Fetcher, deadline: number) {
    this.url = url;
    this.key = key;
    this.fetcher = fetcher;
    this.deadline = deadline;
  }
  async rpc(name: string, body: Record<string, unknown>): Promise<any> {
    if (
      ![
        "recipe_rate_gate",
        "recipe_pilot_access",
        "recipe_issue",
        "recipe_lookup",
        "recipe_reserve",
        "recipe_finish",
      ].includes(name)
    )
      throw new RecipeError("configuration");
    const controller = new AbortController();
    const duration = Math.min(5000, this.deadline - Date.now());
    if (duration <= 0) throw new RecipeError("timeout");
    const timer = setTimeout(() => controller.abort(), duration);
    try {
      const response = await this.fetcher(this.url + "/rest/v1/rpc/" + name, {
        method: "POST",
        headers: {
          apikey: this.key,
          Authorization: "Bearer " + this.key,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      if (!response.ok) throw new RecipeError("unavailable");
      const json = JSON.parse(await boundedText(response, 220000));
      if (typeof json?.code !== "string") throw new RecipeError("unavailable");
      return json;
    } catch {
      throw new RecipeError(
        controller.signal.aborted ? "timeout" : "unavailable",
      );
    } finally {
      clearTimeout(timer);
    }
  }
}
