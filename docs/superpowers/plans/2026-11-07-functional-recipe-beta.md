# Functional recipe beta implementation plan

Goal: permit real recommendations for registered anonymous testers while public approval stays false.
Spec: ../specs/2026-11-07-functional-ai-recipe-beta.md

- [x] Add failing server tests: public policy stays enforced, pilot membership checked before issue/lookup/model, missing/revoked membership denies, pilot user rate limit, no untrusted IP reliance.
- [x] Implement optional pilot mode, Auth-verified user HMAC membership and principal-based rate limit in handler; default public behavior unchanged.
- [x] Add DB migration with RLS/service-only tester allowlist, expiring program (max 7 days), and cumulative reserve guard within program lifetime. Existing budget reservation/settlement remains authoritative.
- [x] Add app registration-ID method and UI; no token shown. Test auth and display.
- [x] Run all server/app tests and review access control/retention/cost guards.
- [x] Deploy disabled first, verify real DB privilege/denial/cap checks. Check model prices before setting test budget. Only then enable pilot with no enrolled public users.
- [x] Verify real Flutter client against backend using one synthetic tester, issue/generation/replay/revocation; record cost. Device install QA remains user-side if no device available.
- [ ] Build same-certificate APK with increased version, update operating docs; report activation and QA limits explicitly.
