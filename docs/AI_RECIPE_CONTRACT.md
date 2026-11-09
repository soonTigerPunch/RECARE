# Shared recipe implementation contract

## Wire format

`POST <SUPABASE_URL>/functions/v1/recipe-recommendations` with publishable key in `apikey`, anonymous access token in `Authorization: Bearer …`.

Request JSON:
```
{"request_id":"uuid", "ingredients":[{"id":"i0","name":"두부","amount":300000,"unit":"G","days_left":0}],"staples":[],"servings":1,"max_minutes":20,"allow_shopping":false,"exclusions":""}
```
Amounts are integer base units exactly as FoodUnit uses: 1000 = 1g/1ml/1개; 1000000 = 1kg/1L. No floating point quantities. Stock groups are exact name + unit family; individual selected lots stay mapped locally. Server never receives local food IDs or expiry/purchase dates, prices, or history.

For ingredients with numeric `amount` and `unit`, the client derives `display_quantity` from those validated values, including when reopening persisted recipes. Model-provided quantity text is retained only when both numeric fields are null.

Success JSON:
```
{"status":"ok","message":"","recipes":[{"title":"두부 구이","servings":1,"minutes":15,"reason":"임박한 두부를 활용해요","ingredients":[{"source_id":"i0","name":"두부","amount":150000,"unit":"G","display_quantity":"150 g","kind":"inventory"}],"steps":["두부를 익혀요"],"warnings":["재료 상태와 익힘을 확인하세요"]}]}
```
`status` is `ok` or `no_match`; no_match has empty recipes and a message. Ingredient kind is `inventory`, `staple`, or `shopping`. Inventory requires valid selected source_id and positive integer amount/unit compatible with stock. Staple/shopping source_id is null; amount/unit may be null for a textual amount. `display_quantity` is always text. Only confirmed staples are allowed as staple. Shopping requires allow_shopping and at most 3 distinct extra items. Every recipe uses at least one stock. Client assigns stable recipe IDs `requestId:index`, uses optional response `generated_at` (ISO timestamp) for result and recipe generatedAt with current response time as a compatibility fallback, and adds local `food_ids` to inventory ingredients when persisting. Server response never needs local IDs. Model uses exactly this schema minus server envelope metadata.

Errors: `{error:{code,message,retryable,retry_at?}}`, HTTP status appropriate. Codes include invalid_request, unauthorized, disabled, daily_limit, budget_limit, in_progress, expired, conflict, timeout, rate_limited, unavailable, configuration, invalid_output. Same request_id+session+payload returns same result without new generation; changed payload is conflict. IDs are session-bound and expire at 24h, with tombstones preventing replay. Auth max session age 30d. Daily quota Korean day, default 5. GET `?request_id=uuid` retrieves only this session's result and never generates; a never-seen ID returns not_found.

Before first generation, client calls `POST ?action=issue` with `{request_id:uuid}`. Server registers issuance/expiry on its own clock and returns `{request_id,expires_at}`. Issuance is idempotent and never resets an existing ID's age. Main POST rejects IDs never issued or expired. Compact tombstones prevent an old ID from starting a new operation after result deletion. No model call or daily recommendation quota is consumed by issuance; abuse rate limits still apply.

## Dart interfaces — domain (`lib/domain/recipes.dart`)

- `const recipeStaples = <String>['소금','설탕','식용유','간장','후추','참기름'];`
- `enum RecipeIngredientKind { inventory, staple, shopping }`
- `RecipeStock({required String id, required List<Food> foods})`: getters name, unit, amount, foodIds; `toRequestJson(DateTime today)`.
- `List<Food> eligibleRecipeFoods(Iterable<Food> foods, DateTime today)` sorted expiry/name; `List<RecipeStock> groupRecipeFoods(Iterable<Food> foods)` groups exact normalized name+family; `Set<String> defaultRecipeFoodIds(Iterable<Food> foods,DateTime today)` picks eligible within 3d capped 10 groups, else earliest 3 groups.
- `RecipeRequest({required String requestId, required List<RecipeStock> stocks, List<String> staples=const [], int servings=1, int? maxMinutes=20, bool allowShopping=false, String exclusions=''})`: fields, date-independent `void validate()` for structural conditions, and `toJson(DateTime today)` which calls validate then rejects expired selected lots. Response replay validates structural conditions and the original stock snapshots without requiring those historical stocks to remain eligible today; actual new recommendation serialization still checks current freshness.
- `RecipeIngredient({required String name, required RecipeIngredientKind kind, String? sourceId, int? amount, FoodUnit? unit, String displayQuantity='', List<String> foodIds=const []})`; all fields public final, `toJson()/fromJson(Map<String,dynamic>)`.
- `Recipe({required String id,required String title,required int servings,required int minutes,required String reason,required List<RecipeIngredient> ingredients,required List<String> steps,required List<String> warnings,required DateTime generatedAt,int schemaVersion=1})`; `toJson()/fromJson`; `shoppingIngredients` getter; `Set<String> stockFoodIds`.
- `RecipeResult({required String requestId,required List<Recipe> recipes,String message='',required DateTime generatedAt})`; `toJson()/fromJson`; static `fromResponse(Map<String,dynamic> json,RecipeRequest request,DateTime now)` validates server response against request including staples/exclusions/quantities/duplicate dishes and attaches local IDs.
- `RecipeSettings({List<String> staples=const [],int servings=1,int? maxMinutes=20,int consentVersion=0})`; `toJson()/fromJson`.
- `RecipeUsage({required Food food,required int amount})`; expected food snapshot stored with persistent cooking draft.
- `CookingOperation({required String id,required String recipeId,required String state,required DateTime day,required List<RecipeUsage> usages})`, state draft/completed/undone; `recordCount` getter.
- `RecipeShoppingResult({required int added,required int existing})`.

## Dart storage (`lib/data/recipe_repository.dart`)

`RecipeRepository(InventoryRepository inventory)` uses same DB (public `Database get database` may be added by storage owner, no second independent handle).

Methods:
- `Future<RecipeSettings> loadSettings()` / `saveSettings(RecipeSettings)`;
- `Future<void> saveRecent(RecipeResult)`; `Future<List<RecipeResult>> loadRecent()`; `clearRecent()`;
- `Future<List<Recipe>> loadFavorites()` newest first; `Future<void> setFavorite(Recipe recipe,bool value)` idempotent limit100; `Future<bool> isFavorite(String recipeId)`; `Future<void> restoreFavorite(Recipe recipe,DateTime savedAt)` if needed preserving date;
- `Future<DateTime?> favoriteSavedAt(String recipeId)` supplies persistent original date for undo.
- `Future<CookingOperation> beginCooking(Recipe recipe,DateTime today,{bool newRound=false})`: return latest draft/completed; newRound explicitly generates new persistent ID;
- `Future<CookingOperation?> latestCooking(String recipeId)`; `Future<void> saveCookingDraft(String operationId,List<RecipeUsage> usages,DateTime today)`;
- `Future<int> completeCooking(String operationId,List<RecipeUsage> usages,DateTime today)` atomic revalidate against passed snapshots and draft day; returns count; duplicate completed returns same count;
- `Future<bool> undoCooking(String operationId)` atomic latest-record restrictions;
- `Future<RecipeShoppingResult> addShoppingBatch(String requestId,List<ShoppingItem> items)` atomic idempotent;
- `Future<String?> loadValue(String key)` / `Future<void> saveValue(String key,String? value)` for anonymous token/session state. Exclusions never stored.

## Dart client (`lib/services/recipe_client.dart`)

`abstract class RecipeClient { Future<RecipeResult> recommend(RecipeRequest request,DateTime now); Future<RecipeResult?> lookup(RecipeRequest request,DateTime now); void cancel(); void close(); }`
`RecipeClientException implements Exception`: `code,message,retryable` + nullable `DateTime retryAt`.
`SupabaseRecipeClient({required RecipeRepository repository,String? supabaseUrl,String? publishableKey})` uses --dart-define RECARE_SUPABASE_URL / RECARE_SUPABASE_PUBLISHABLE_KEY. No fake response in production. Missing config yields friendly unavailable state. cancel invalidates response for current caller, lookup same request never creates.

## UI (`lib/ui/recipes/recipe_pages.dart`)

`RecipeHubPage({required InventoryRepository inventory,required RecipeRepository repository,required RecipeClient client,required DateTime Function() clock, String initialPage='input',Future<void> Function()? onRegister})` has full-screen input/recent/favorites entry. Client owned by parent, not closed by page. UI may split additional files in same directory.

Root integrates home routes, injects optional RecipeClient into RecareApp and passes shared repositories; refreshes inventory/reminders after recipe route returns. Home has recipe entry and favorites even when stock empty, recent link only when saved results exist. UI loads stock live, validates on resume/before request/save, suppresses stale async callbacks; no real API in tests.


## Menu-first flow (1.2.1)

POST with `stage: "menus"` plus the original request fields returns `{status,message,menus:[{id:"m0",title:"두부조림"}],generated_at,generation}`. Only titles are generated; `recipes` is absent. Up to five distinct feasible options, normally three to five. If the conditions permit fewer, return fewer; no_match has an empty list. Names are checked for normalized/known alias duplicates and obvious forbidden ingredients; semantic feasibility remains a model limitation.

For detail, issue a separate child UUID and POST the same input conditions plus `stage:"detail",parent_request_id,menu_id`. The server verifies the completed, unexpired menu parent in the same session, binds input hash excluding request_id, and selects the stored title. Caller-supplied titles are not accepted. Result is the existing recipes shape with exactly the selected dish (or no_match). Both operations use atomic reservation/settlement and session quota. GET by either request_id only replays its own saved result and never generates. Omitting stage retains legacy compatibility.

`generation` includes observed calls, input/output token counts and cost_micro estimated from configured prices. This is not a billing invoice. Unknown provider usage remains conservatively charged. A successful user flow is normally two model calls; correction may add one per stage (at most four total). Reopening an existing selected detail uses the child result cache, not a new child UUID.
