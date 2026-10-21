# Everyday usability Implementation Plan

> **For agentic workers:** Use the parallel-agent workflow for independently owned data and Android reminder domains, then integrate in this session. Steps use checkbox syntax for tracking.

**Goal:** Implement the five requested everyday usability improvements in the existing RE:CARE project.
**Architecture:** Extend SQLite transaction APIs and pure domain types; implement reminders through a small Android method channel; connect focused Flutter pages to the existing app without changing its three primary navigation destinations.
**Tech Stack:** Flutter 3.47.6, Dart 3.13.5, sqflite, Android Kotlin/AlarmManager/NotificationManager.
**Spec:** `docs/superpowers/specs/2026-10-21-everyday-usability.md`

## Global Constraints
- Preserve application ID, existing inventory and integer monetary allocation.
- Add a non-destructive SQLite v1 → v2 migration.
- Korean interface; Android API 29 minimum; no server or external product API.
- No copying previous expiry/price into a new purchase, no fabricated savings.
- Local changes only; no remote push or release publication.

## Review Focus
- Undo followed by retry must not duplicate stock or invalidate later monetary allocation.
- A partially invalid batch or stale shopping entry must roll back all writes.
- Permission denial, reboot and local timezone changes must not cause false reminder status or duplicate daily notifications.
- Narrow screens, large fonts and keyboards must leave save/cancel/undo reachable.
- Null prices and historical records must stay distinct from zero and new reason-coded entries.

## Task 1: persistence and business rules
Files: `lib/domain/inventory.dart`, new `lib/domain/shopping.dart`, new `lib/domain/waste_insights.dart`, `lib/data/inventory_repository.dart`; tests in `test/usability_repository_test.dart` and `test/waste_insights_test.dart`.
Interfaces: `WasteReason {tooMuch, forgot, disliked, other}`, `FoodRecord.wasteReason`; `ShoppingItem(id,name,unit,amount,created)`; `loadShoppingList()`, `addShoppingItem(ShoppingItem)`, `removeShoppingItem(String)`, `saveBatch(List<Food>, {Map<String,String> shoppingItemsByFoodId = const {}})`, `undoProcess(String recordId)` returning `Future<bool>`; `hasProcessingHistory(String foodId)`; `process` gains optional `WasteReason? wasteReason`. `InventorySnapshot.records` remains active-only.
- [x] Add tests for v1 fixture preservation, idempotent latest-only undo and exact reprocessing cost, duplicate shopping entries and atomic checkout.
- [x] Run focused tests and confirm expected missing-feature failures.
- [x] Implement schema migration and transactional methods; add explicit malformed-input validation.
- [x] Run focused tests and preserve all existing tests.

## Task 2: Android local daily digest
Files: Android MainActivity, new receiver/scheduler Kotlin classes, AndroidManifest; new `lib/services/reminder_service.dart`, `lib/ui/reminder_settings.dart`, `test/reminder_service_test.dart`.
Interfaces: `ReminderSettings(enabled,hour,minute)`; `ReminderService` has `isSupported`, `loadSettings()`, `requestPermission()`, `configure(ReminderSettings)`, `consumeOpenUrgent()` and `Stream<void> openUrgentRequests`. `ReminderSettingsCard(service)` owns its settings UI.
- [x] Test bridge behavior and settings enable/denial/save failure with platform calls mocked only at the native boundary.
- [x] Implement persisted native scheduling, permission handling, fresh DB reads, once-per-local-day gate, cancel/reboot/time change and notification-open routing.
- [x] Run focused tests and compile the Android target during final integration.

## Task 3: batch registration and shopping flow
Files: new `lib/ui/batch_registration.dart`, new `lib/ui/shopping_page.dart`; `test/batch_registration_test.dart`, `test/shopping_page_test.dart`.
Interfaces: `BatchRegistrationPage(repository, clock, initialItems = const [])` returns bool via Navigator; `ShoppingPage(repository, clock)` uses the batch page for checkout.
- [x] Test multiple item validation, untouched shopping list on cancel/failure and successful atomic purchase registration.
- [x] Implement recent/catalogue selection and a form per selected item with manual entry, quantity/unit/date/optional price.
- [x] Implement shopping additions/removal, on-hand stock hint and multi-item checkout.
- [x] Verify narrow-screen interactions and repository-backed outcomes.

## Task 4: app integration and insights
Files: `lib/main.dart`, new `lib/ui/waste_insights_view.dart`, integration tests.
- [x] Test inventory quick actions and undo restore, waste reason persistence, navigation to batch/shopping and notification urgent filter.
- [x] Reuse ProcessDialog with optional record-ID callback; keep existing bool results compatible. Add reason choices only for waste.
- [x] Connect list quick actions, Undo SnackBar, batch and shopping entry points, reminder settings and weekly insights.
- [x] Ensure detail edit/delete restrictions use persisted history (including undone records), and refresh on return/lifecycle.

## Task 5: validate and hand off
- [x] Run `flutter analyze --no-pub` and complete `flutter test --no-pub --reporter expanded`.
- [x] Run `flutter build apk --debug --no-pub`; inspect artifact package/version.
- [x] Independent review of the full diff; fix verified defects and re-run affected checks.
- [x] Update README, migration/development notes and cloud setup status with observed results and device-only limitations.
- [x] Leave requested implementation in the project folder and report exact locations; no publish/push.


## Completion evidence (2026-10-21 KST)

- Full Flutter suite: 102 passed; analyzer: no issues.
- Kotlin reminder policy: 9 standalone JVM assertions passed.
- Final Android debug APK build succeeded; com.detabev.recare, 1.0.3+4, minSdk29/targetSdk36 retained.
- Independent review defects fixed: route-independent undo, keyboard-visible batch footer, non-rescheduling reminder reads. Reviewer confirmed fixes.
- Physical-device notification delivery/permission/reboot smoke checks remain explicitly outside verified host results; no device connected.
- Changes remain local in requested cloud project; no push or release.
