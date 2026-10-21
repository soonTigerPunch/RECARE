# RE:CARE everyday usability

User request: implement the five proposed improvements in the existing project folder. Use `/workspace/RECARE-main`; the PC Desktop directory is not mounted. Work in place on `feature/everyday-usability`.

## Scope and behavior

1. Inventory rows offer 먹음/폐기 actions using the existing portion dialog. A successful action offers 실행 취소. Undo restores remaining stock and removes that action from active totals, but retains an audit tombstone and request ID. Only the latest active action on a food can be undone so monetary allocation remains correct. Repeated undo and a retried original request never double-adjust inventory.
2. Batch registration lets people select multiple catalogue/recent items, then edit each quantity, unit, expiry and optional price on one page. No expiry or purchase price is copied from history. All entries validate and save atomically; failed validation writes none. Selection and typed values survive failures.
3. Optional local Android daily digest, initially off, default 19:00, adjustable time. It covers stock with expiry on/before today + 3 days, including overdue stock. Read current SQLite inventory when the alarm fires, skip empty summaries and limit delivery to once per local day. Android 13+ permission is requested only when enabling. Denial does not show enabled status. Disable cancels alarms and visible digest. Reboot/timezone/app update reschedule. Use inexact alarms (device power management may delay delivery). A notification opens the urgent inventory filter. No server or new package is required.
4. Persistent shopping list: manually add name/quantity/unit or add a finished food with its original quantity. Normalize equivalent name/unit/amount to avoid duplicate pending entries. Show matching on-hand stock separately from desired purchase quantity. Multi-select purchased items into batch registration; remove shopping entries only in the same successful transaction that inserts the new foods. Cancel or failure preserves the shopping entries.
5. Waste processing optionally records one of tooMuch/forgot/disliked/other, with Korean labels and a skip option. Existing records have unknown reasons. Weekly insights show actual waste counts/known amounts, top wasted names and the most common recorded reason with a practical purchasing hint. Never infer saved money or convert unknown prices to zero.

## Persistence and compatibility

Keep application ID `com.detabev.recare`, database name `recare.db`, existing food schema and exact integer cost calculations. Add schema version 2 migration for record reason/voided columns and shopping table; no destructive reset. Existing Kotlin v1 fixtures and Flutter v1 data migrate intact. Record-backed edit/delete restrictions remain enforced. Expose active records separately from per-food history restrictions so undo cannot make UI claim a historically restricted food is editable/deletable.

## Organization and validation

Keep main.dart as integration only; separate batch registration, shopping/insights UI and reminder bridge. Flutter 3.47.6 / Dart 3.13.5, Android API 29 minimum. Korean UI, existing design tokens, narrow screens/large text supported. Add behavior tests before implementation for migration, undo ordering/idempotency/rounding, atomic batch/checkout, shopping persistence, reason reporting and permission/configuration boundaries. Run all existing tests, analyze and Android debug APK build. Real notification delivery requires an Android device and must be reported separately if unavailable.

## Authorization and execution

The user's explicit request to write/apply the proposed features authorizes these local reversible changes. Do not push or publish. Coordinate independent data and notification implementations with bounded file ownership, then integrate and review. Earlier SDK setup is retained; the full JDK is now installed, and APK verification remains outstanding.
