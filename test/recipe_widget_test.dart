import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/recipe_repository.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/recipes.dart';
import 'package:recare/services/recipe_client.dart';
import 'package:recare/ui/design_system.dart';
import 'package:recare/ui/recipes/recipe_pages.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeRecipeClient implements RecipeClient {
  int calls = 0;
  int lookups = 0;
  int cancellations = 0;
  RecipeRequest? last;
  Completer<RecipeResult>? pending;
  RecipeResult? result;
  Object? error;
  @override
  Future<RecipeResult> recommend(RecipeRequest request, DateTime now) async {
    calls++;
    last = request;
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    return result!;
  }

  @override
  Future<RecipeResult?> lookup(RecipeRequest request, DateTime now) async {
    lookups++;
    expect(request.requestId, last!.requestId);
    return result;
  }

  @override
  void cancel() {
    cancellations++;
  }

  @override
  void close() {}
}

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late InventoryRepository inventory;
  late RecipeRepository repository;
  late FakeRecipeClient client;
  var now = DateTime(2026, 11, 4, 12);
  Food food(String id, String name, {int days = 0, int amount = 300000}) =>
      Food(
        id: id,
        name: name,
        unit: FoodUnit.gram,
        total: amount,
        expiry: now.add(Duration(days: days)),
        price: 1000,
        created: now,
      );
  Recipe recipe({
    String id = 'request:0',
    List<RecipeIngredient>? ingredients,
  }) => Recipe(
    id: id,
    title: '두부 구이',
    servings: 1,
    minutes: 15,
    reason: '두부를 활용해요',
    ingredients:
        ingredients ??
        [
          RecipeIngredient(
            name: '두부',
            kind: RecipeIngredientKind.inventory,
            sourceId: 'i0',
            amount: 150000,
            unit: FoodUnit.gram,
            displayQuantity: '150 g',
            foodIds: ['tofu'],
          ),
        ],
    steps: ['두부를 충분히 익혀요'],
    warnings: ['재료 상태를 확인하세요'],
    generatedAt: now,
  );
  setUp(() async {
    now = DateTime(2026, 11, 4, 12);
    temp = await Directory.systemTemp.createTemp('recare-recipe-ui-');
    inventory = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/test.db',
    );
    repository = RecipeRepository(inventory);
    client = FakeRecipeClient();
    await inventory.save(food('tofu', '두부'));
    client.result = RecipeResult(
      requestId: 'result',
      recipes: [recipe()],
      generatedAt: now,
    );
  });
  tearDown(() async {
    await inventory.close();
    await temp.delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (i >= 3 &&
          find
              .byKey(const ValueKey('recipe-initial-loading'))
              .evaluate()
              .isEmpty &&
          find.byKey(const ValueKey('recipe-saving')).evaluate().isEmpty &&
          find.text('기록 확인 중…').evaluate().isEmpty &&
          (find.text('재고 확인 중…').evaluate().isEmpty ||
              find.text('확인하고 추천받기').evaluate().isNotEmpty)) {
        await tester.pump(const Duration(milliseconds: 300));
        return;
      }
    }
    fail('Recipe page did not settle');
  }

  Future<void> open(
    WidgetTester tester, {
    String page = 'input',
    double scale = 1,
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? RecareTheme.dark : RecareTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RecipeHubPage(
          inventory: inventory,
          repository: repository,
          client: client,
          clock: () => now,
          initialPage: page,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'selection excludes expired and requires explicit transmission consent',
    (tester) async {
      await tester.runAsync(
        () => inventory.save(food('expired', '지난 우유', days: -1)),
      );
      await tester.runAsync(() => inventory.save(food('later', '당근', days: 8)));
      await open(tester);
      expect(client.calls, 0);
      expect(find.textContaining('지난 재료 1개'), findsOneWidget);
      expect(find.text('지난 우유'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('recipe-generate')));
      await settle(tester);
      expect(find.text('확인하고 추천받기'), findsOneWidget);
      expect(client.calls, 0);
      await tester.tap(find.text('확인하고 추천받기'));
      await settle(tester);
      expect(client.calls, 1);
      expect(client.last!.stocks.single.foodIds, ['tofu']);
      expect(client.last!.staples, isEmpty);
      expect(
        (await tester.runAsync(repository.loadSettings))!.consentVersion,
        1,
      );
    },
  );
  testWidgets('cancel suppresses late response and keeps memory input', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.saveSettings(RecipeSettings(consentVersion: 1)),
    );
    client.pending = Completer<RecipeResult>();
    await open(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('recipe-exclusions')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('recipe-exclusions')),
      '땅콩',
    );
    await tester.tap(find.byKey(const ValueKey('recipe-generate')));
    await settle(tester);
    expect(find.text('추천 취소'), findsOneWidget);
    await tester.tap(find.text('추천 취소'));
    await tester.pump();
    client.pending!.complete(client.result!);
    await settle(tester);
    expect(find.byKey(const ValueKey('recipe-generate')), findsOneWidget);
    expect(find.text('두부 구이'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('recipe-exclusions')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('recipe-exclusions')))
          .controller!
          .text,
      '땅콩',
    );
    expect(client.cancellations, 1);
    expect((await tester.runAsync(repository.loadRecent))!, isEmpty);
  });
  testWidgets('favorites survive recent clearing and work without a request', (
    tester,
  ) async {
    await tester.runAsync(() => repository.saveRecent(client.result!));
    await tester.runAsync(() => repository.setFavorite(recipe(), true));
    await tester.runAsync(repository.clearRecent);
    await open(tester, page: 'favorites');
    expect(find.text('두부 구이'), findsOneWidget);
    await tester.tap(find.text('두부 구이'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.textContaining('두부를 충분히 익혀요'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('두부를 충분히 익혀요'), findsOneWidget);
    expect(client.calls, 0);
    await tester.tap(find.byTooltip('두부 구이 즐겨찾기 해제').last);
    await settle(tester);
    expect((await tester.runAsync(repository.loadFavorites))!, isEmpty);
    await tester.tap(find.text('실행 취소').hitTestable().last);
    await settle(tester);
    expect((await tester.runAsync(repository.loadFavorites))!, hasLength(1));
  });
  testWidgets('cooking saves integer amount once and can undo all records', (
    tester,
  ) async {
    await tester.runAsync(() => repository.setFavorite(recipe(), true));
    await open(tester, page: 'favorites');
    await tester.tap(find.text('두부 구이'));
    await settle(tester);
    await tester.tap(find.text('만들었어요 · 사용량 확인'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('recipe-use-tofu')),
      '100',
    );
    await tester.tap(find.byKey(const ValueKey('recipe-cooking-save')));
    await settle(tester);
    final snapshot = await tester.runAsync(inventory.load);
    expect(snapshot!.foods.single.remaining, 200000);
    expect(snapshot.records, hasLength(1));
    await tester.tap(find.text('실행 취소').hitTestable().last);
    await settle(tester);
    expect(
      (await tester.runAsync(inventory.load))!.foods.single.remaining,
      300000,
    );
    expect(client.calls, 0);
  });
  testWidgets('small dark phone and large text keep actions usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, scale: 2, dark: true);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('recipe-exclusions')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('recipe-exclusions')),
      '우유',
    );
    expect(
      find.byKey(const ValueKey('recipe-generate')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('fractional gram usage from kilogram stock stays exact', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await inventory.save(
        Food(
          id: 'tofu',
          name: '두부',
          unit: FoodUnit.kilogram,
          total: 1000000,
          expiry: now,
          price: 1000,
          created: now,
        ),
      );
      await repository.setFavorite(recipe(), true);
    });
    await open(tester, page: 'favorites');
    await tester.tap(find.text('두부 구이'));
    await settle(tester);
    await tester.tap(find.text('만들었어요 · 사용량 확인'));
    await settle(tester);
    final input = find.byKey(const ValueKey('recipe-use-tofu'));
    expect(tester.widget<TextField>(input).controller!.text, '150');
    await tester.enterText(input, '100.5');
    await tester.tap(find.byKey(const ValueKey('recipe-cooking-save')));
    await settle(tester);
    expect(
      (await tester.runAsync(inventory.load))!.foods.single.remaining,
      899500,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('keyboard inset keeps recommendation button above keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await open(tester, scale: 2, dark: true);
    final button = find.byKey(const ValueKey('recipe-generate'));
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(340));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
