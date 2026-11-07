// Explicit opt-in only. No API key is read by this test; it exercises the real
// Flutter client and an administrator enrolls its synthetic user out-of-band.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/recipe_repository.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/recipes.dart';
import 'package:recare/services/recipe_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'live Flutter client issues, generates, replays and denies revoked tester',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('recare-live-');
      final inventory = await InventoryRepository.open(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      final client = SupabaseRecipeClient(
        repository: RecipeRepository(inventory),
      );
      try {
        final now = DateTime.now();
        final id = await client.testerId(now);
        expect(id, matches(RegExp(r'^[a-f0-9]{64}$')));
        final request = RecipeRequest(
          requestId: '00000000-0000-4000-8000-000000000007',
          stocks: [
            RecipeStock(
              id: 'i0',
              foods: [
                Food(
                  id: 'live-tofu',
                  name: '두부',
                  unit: FoodUnit.gram,
                  total: 300000,
                  price: 0,
                  expiry: now.add(const Duration(days: 2)),
                  created: now,
                ),
              ],
            ),
          ],
          staples: ['소금', '식용유'],
        );
        await expectLater(
          client.recommend(request, now),
          throwsA(
            isA<RecipeClientException>().having(
              (e) => e.code,
              'code',
              'not_enrolled',
            ),
          ),
        );
        await File('/tmp/recare-live-registration').writeAsString(id);
        for (
          var i = 0;
          i < 180 && !await File('/tmp/recare-live-enrolled').exists();
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        expect(await File('/tmp/recare-live-enrolled').exists(), true);
        final result = await client.recommend(request, now);
        expect(result.recipes, isNotEmpty);
        final replay = await client.lookup(request, now);
        expect(replay!.recipes.first.title, result.recipes.first.title);
        await File('/tmp/recare-live-generated').writeAsString('done');
        for (
          var i = 0;
          i < 180 && !await File('/tmp/recare-live-revoked').exists();
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        expect(await File('/tmp/recare-live-revoked').exists(), true);
        await expectLater(
          client.lookup(request, now),
          throwsA(
            isA<RecipeClientException>().having(
              (e) => e.code,
              'code',
              'not_enrolled',
            ),
          ),
        );
      } finally {
        client.close();
        await inventory.close();
        await dir.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RECARE_LIVE_TEST'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
