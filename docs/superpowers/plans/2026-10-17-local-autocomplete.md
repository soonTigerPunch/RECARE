# Local ingredient autocomplete implementation plan

> Execution: implement inline with test-driven-development and executing-plans. User explicitly requested proceeding with the agreed feature on the existing Flutter project; preserve prior uncommitted copy and documentation changes.

**Goal:** Offer image-backed curated ingredients and recent registrations, filling name and quantity only.
**Architecture:** Small bundled Dart catalogue plus up to 200 recent foods read once when registration opens. A pure in-memory index normalizes and deduplicates results, returning at most five. Representative vector illustrations are inferred from ingredient names, so existing Food models and SQLite schema remain unchanged.
**Stack:** Existing Flutter/Dart/sqflite only; no new package or server.
**Spec:** docs/DEVELOPMENT_HISTORY.md section 9 and the user's instruction to proceed.

## Constraints and decisions
- Keep app ID, SQLite version 1, existing records, monetary allocation, deletion policy and three navigation tabs.
- Suggestions expose no historical expiry or price. Selecting a new suggestion clears those purchase-specific fields for confirmation; manual quantity/name entry remains available.
- Autocomplete is for new registration only, never a way around historical edit restrictions.
- Use original lightweight representative vector images, explicitly labelled representative images; no external product photo or runtime image download.
- Include verified Seoul Milk low-fat 200ml/500ml/1L examples and generic foods whose amounts are editable starting quantities.
- Existing current-project work is preserved in place. No automatic publication or commit of unrelated changes.

## Work
- [x] Add failing widget coverage for partial Korean product lookup and safe selection.
- [x] Implement pure catalogue/index with ranking, alias lookup, deduplication, blank/unknown input and result bounds; test original quantities and immutability.
- [x] Read a bounded recent-registration list from existing foods, retaining finished items and surviving restart; add repository coverage.
- [x] Add representative illustrations and registration suggestion rows, a selected-item preview, async-history fallback and manual entry. Show representative artwork on matching detail names.
- [x] Verify save/reopen, prior-history pricing, no results, edit restrictions, small screen/keyboard, and full suite.
- [x] Analyze, render examples, build Android debug APK, document the new functionality and limitations.

## Review focus
1. Previous purchases must not silently assign a date or price to new stock.
2. Picking a result then renaming it must not leave an unrelated image selected.
3. Results must remain tappable on 320px screens with keyboard and large text.
4. Recent-list failure must leave catalogue and manual registration usable.
5. Finished/duplicate prior purchases must yield original amount, bounded results, no mutation of saved records.

## Progress
Implementation started. Baseline from preceding task: 49 tests and static analysis passed. Current workspace already contains prior user-authorized copy/documentation updates.


### Completion evidence (2026-10-17)
- Partial query/selection widget tests were observed failing before implementation, then passing.
- Fixed focus loss from conditional list-child shifts with a stable widget key; inherited catalogue aliases when history deduplicates base choices.
- `flutter analyze --no-pub`: no issues; full suite: 67 passed.
- `flutter test --no-pub tool/preview.dart`: passed; 13 phone-sized captures reviewed.
- `flutter build apk --debug --no-pub`: succeeded for 1.0.3+4.
- Fresh final read-only review of catalogue, widget state, repository, main integration and tests: no actionable findings.
- Initial automatic approval review was temporarily unavailable due usage limits; resumed successfully after the user's continue instruction.
- No schema migration, new package, commit, push, publication, or current-version device installation.
- Work remains in the user-designated Flutter project, preserving prior local microcopy/documentation changes.

### Follow-up: source publication
2026-10-17: the user explicitly requested a GitHub push after local completion. Prepare the implemented source, tests, documentation and screenshots for origin/main. APK publication remains separate; the existing public Release is v1.0.2-mvp.
