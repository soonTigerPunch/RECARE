# AI Recipe Implementation Plan

> **For agentic workers:** Use the focused task boundaries below; independent server and Flutter modules may run in parallel. Use test-first implementation and review before integration.

**Goal:** Implement the approved full AI recipe specification with Supabase/OpenAI integration and mock-only verification.

**Architecture:** Flutter keeps inventory and recipe history locally; an authenticated Supabase Edge Function validates structured OpenAI responses. PostgreSQL RPCs reserve quotas and jobs atomically. No API secret is shipped to the app.

**Tech Stack:** Existing Flutter/Dart/SQLite, Dart HttpClient, TypeScript/Web APIs, Supabase PostgreSQL and Edge Functions, Node built-in tests.

**Spec:** `docs/superpowers/specs/2026-11-05-ai-recipe-supabase.md` and user attachment `2026-11-04-ai-recipe-design.md`.

## Global Constraints

- Full original scope/defaults approved; no real OpenAI calls, even for key validation.
- No environment publication, external messages, account creation, or production activation.
- Existing inventory amounts remain integers; g/kg and ml/L only, never cross-family conversion.
- No OpenAI key in app, Git, logs, exceptions, or HTTP response.
- Original exclusion text remains request-memory-only on device.
- Recent requests 5; favorites 100; request ingredients 1–10 types; servings 1–4; time 10/20/30/null; max recipes 3.
- Server 30s/app 35s; at most two model calls, correction only when all candidates fail.
- Deployment requires user-owned Supabase project, privacy/integrity choices and numeric service budgets.

## Review Focus

- Mid-write database failure must roll back all inventory and costs; test injected triggers.
- A canceled or timed-out request must never create a second generation silently; test late completion and same-ID retry.
- Favorites must survive recent-history cleanup and offline use; test DB reopen and deletion.
- Malformed model quantities/IDs/staples must not bypass inventory/purchase conditions; test literal fixtures.
- Session/quota races must not spend twice or reveal another user's result; test server boundary and PostgreSQL reservations.

## Contract

The shared interfaces are documented in `docs/AI_RECIPE_CONTRACT.md`. Implementers must preserve them and coordinate any necessary changes before editing another module.

### Task 1: Recipe domain and transactional local storage

Files: `lib/domain/recipes.dart`, `lib/data/recipe_repository.dart`, `lib/data/inventory_repository.dart`, `test/recipe_domain_test.dart`, `test/recipe_repository_test.dart`.

- [x] Write and run failing tests for selection, request privacy, integer validation, history/favorites, migrations and atomic cooking/shopping.
- [x] Implement the domain contract and SQLite v4 on the existing database connection; recipe repository delegates atomic inventory writes through public inventory repository methods.
- [x] Verify retry after reopen, conflict rollback, latest-only undo, history/favorite independence and existing migrations.

### Task 2: Supabase server and OpenAI boundary

Files: `supabase/config.toml`, `supabase/functions/recipe-recommendations/*`, `supabase/migrations/*`, `server_tests/*`, `docs/AI_RECIPE_SERVER.md`.

- [x] Write and run failing Node tests for input/output validation, model responses, duplicate jobs, auth failures and quotas.
- [x] Implement fixed structured-output Responses call, persistent reservation RPCs, encrypted short-lived results, authenticated same-job retrieval, safe errors and disabled-by-default operation.
- [x] Add deploy/run instructions without deploying; verify no external OpenAI calls and document SQL execution evidence/limitations.

### Task 3: Recipe screens

Files: `lib/ui/recipes/*`, `test/recipe_widget_test.dart`.

- [x] Write and run failing widget tests for recipe selection, consent, explicit generation, favorites, cooking and cancellation.
- [x] Implement input/results/detail/recent/favorite/cooking/shopping pages against the shared repository/client contracts.
- [x] Verify small screen/large text/dark mode, late cancellation response, offline favorites, and preservation of input/exclusions only in memory.

### Task 4: HTTP client, home and platform integration

Files: `lib/services/recipe_client.dart`, `lib/main.dart`, `android/app/src/main/AndroidManifest.xml`, `test/recipe_client_test.dart`, `test/recipe_integration_test.dart`.

- [x] Write and run failing tests around HTTP/auth/refresh/error mapping, forbidden credential configuration, and home navigation.
- [x] Implement Supabase anonymous auth and same-ID recommendation requests with injected transport; save refresh token in local application DB, never output it.
- [x] Integrate home entry points and injectable client; retain existing expiry popup and reminder refresh behavior.

### Task 5: Integration review and release evidence

Files: `README.md`, `docs/AI_RECIPES.md`, plan checklist and tests as required.

- [x] Run new server and Flutter tests, full existing Flutter suite, static analysis, release build where supported.
- [x] Independent review of inventory, security and spec completeness; fix material issues and rerun relevant checks.
- [x] Document configuration, mock verification and production activation prerequisites. Do not claim deployment, actual model quality or real-device QA.

## Handoff status

Implementation and local mock/database verification are complete. Supabase account/project creation, production budgets, privacy/integrity policy, deployment and funded OpenAI evaluation remain external activation prerequisites; none was performed. Review findings were fixed for numeric display, exact kg/L entry, keyboard insets, stale result context, disposed undo callbacks, midnight replay, provider cost settlement, strict units and obvious undeclared ingredients.
