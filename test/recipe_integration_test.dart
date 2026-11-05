import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/preferences.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/recipes.dart';
import 'package:recare/main.dart';
import 'package:recare/services/recipe_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _NoNetworkClient implements RecipeClient {
  int requests = 0;
  @override
  Future<RecipeResult> recommend(RecipeRequest request, DateTime now) async {
    requests++;
    throw StateError('Home navigation must never request recommendations');
  }

  @override
  Future<RecipeResult?> lookup(RecipeRequest request, DateTime now) async =>
      null;
  @override
  void cancel() {}
  @override
  void close() {}
}

void main() {
  sqfliteFfiInit();
  testWidgets(
    'home opens recipes and empty-stock favorites without calling AI',
    (tester) async {
      final temp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('recare-home-recipe-'),
      );
      final repo = await tester.runAsync(
        () => InventoryRepository.open(
          factory: databaseFactoryFfi,
          databasePath: '${temp!.path}/app.db',
        ),
      );
      final client = _NoNetworkClient();
      final today = DateTime(2026, 11, 5);
      await tester.runAsync(
        () => repo!.save(
          Food(
            id: 'tofu',
            name: '두부',
            unit: FoodUnit.gram,
            total: 300000,
            expiry: today,
            price: null,
            created: today,
          ),
        ),
      );
      // Malformed optional recommendation cache must not hide offline inventory.
      await tester.runAsync(
        () => repo!.database.insert('recipe_recent', {
          'request_id': 'damaged-cache',
          'result_json': '{invalid',
          'generated_at': today.toUtc().toIso8601String(),
        }),
      );
      await tester.pumpWidget(
        RecareApp(
          automaticCheckIns: false,
          recipeClient: client,
          repositoryFactory: () async => repo!,
          clock: () => today,
          preferencesFactory: () async =>
              PreferencesStore('${temp!.path}/prefs.json'),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 50; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await settle();
      expect(find.byKey(const ValueKey('home-recipes')), findsOneWidget);
      await tester.runAsync(() => repo!.database.delete('recipe_recent'));
      await tester.tap(find.byKey(const ValueKey('home-recipes')));
      await settle();
      expect(find.text('AI 레시피'), findsWidgets);
      expect(client.requests, 0);
      await tester.tap(find.byType(BackButton).first);
      await settle();
      // Favorites remain accessible even if stock disappears.
      await tester.runAsync(() => repo!.deleteFood('tofu'));
      await tester.tap(find.byKey(const ValueKey('home-recipes')));
      await settle();
      await tester.tap(find.byType(BackButton).first);
      await settle();
      final favorites = find.byKey(const ValueKey('home-recipe-favorites'));
      await tester.scrollUntilVisible(
        favorites,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('home-page')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(favorites);
      await settle();
      expect(find.textContaining('즐겨찾기'), findsWidgets);
      expect(client.requests, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await repo!.close();
        await temp!.delete(recursive: true);
      });
    },
  );
}
