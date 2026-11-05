import { configFromEnv, createHandler } from "./handler.ts";
// Importing core modules under Node never binds a server or reads live secrets.
const runtime = (globalThis as any).Deno;
if (runtime?.serve)
  runtime.serve(
    createHandler(configFromEnv((name: string) => runtime.env.get(name))),
  );
