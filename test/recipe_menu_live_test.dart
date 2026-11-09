// Explicit opt-in real network test: two generation jobs maximum, administrator
// enrolls this synthetic user out of band. Never prints tokens or private keys.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/recipe_repository.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/recipes.dart';
import 'package:recare/services/recipe_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

void main() {
  test(
    'real menus, chosen detail, cached replay and revoked tester',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('recare-menu-live-');
      final inventory = await InventoryRepository.open(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/db',
      );
      final repository = RecipeRepository(inventory);
      final client = SupabaseRecipeClient(repository: repository);
      final now = DateTime.now();
      final stocks = ['두부', '양파', '달걀'].indexed
          .map(
            (e) => RecipeStock(
              id: 'i${e.$1}',
              foods: [
                Food(
                  id: 'synthetic-${e.$1}',
                  name: e.$2,
                  unit: e.$1 == 2 ? FoodUnit.piece : FoodUnit.gram,
                  total: e.$1 == 2 ? 2000 : 300000,
                  price: 0,
                  expiry: now.add(const Duration(days: 2)),
                  created: now,
                ),
              ],
            ),
          )
          .toList();
      final parent = RecipeRequest(
        requestId: const Uuid().v4(),
        stocks: stocks,
        staples: ['소금', '식용유', '간장'],
      );
      try {
        final id = await client.testerId(now);
        await File('/tmp/recare-menu-live-registration').writeAsString(id);
        for (
          var i = 0;
          i < 180 && !await File('/tmp/recare-menu-live-enrolled').exists();
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        expect(await File('/tmp/recare-menu-live-enrolled').exists(), true);
        final menus = await client.recommendMenus(parent, now);
        expect(menus.menus.length, inInclusiveRange(3, 5));
        final again = await client.lookupMenus(parent, now);
        expect(
          again!.menus.map((m) => m.title),
          menus.menus.map((m) => m.title),
        );
        final child = RecipeRequest(
          requestId: const Uuid().v4(),
          stocks: stocks,
          staples: parent.staples,
        );
        final selected = menus.menus.first;
        final detail = await client.recommendMenuDetail(
          child,
          parent.requestId,
          selected.id,
          now,
        );
        expect(detail.recipes.length, 1);
        expect(detail.recipes.single.title, selected.title);
        final replay = await client.lookupMenuDetail(
          child,
          parent.requestId,
          selected.id,
          now,
        );
        expect(replay!.recipes.single.title, selected.title);
        final auth = jsonDecode(
          (await repository.loadValue('recipe.auth'))!,
        ) as Map<String, dynamic>;
        Future<Map<String, dynamic>> raw(String requestId) async {
          final http = HttpClient();
          try {
            final req = await http.getUrl(
              Uri.parse(
                '${const String.fromEnvironment('RECARE_SUPABASE_URL')}/functions/v1/recipe-recommendations?request_id=$requestId',
              ),
            );
            req.headers.set(
              'apikey',
              const String.fromEnvironment('RECARE_SUPABASE_PUBLISHABLE_KEY'),
            );
            req.headers.set('Authorization', 'Bearer ${auth['access_token']}');
            final res = await req.close();
            expect(res.statusCode, 200);
            return jsonDecode(await utf8.decoder.bind(res).join())
                as Map<String, dynamic>;
          } finally {
            http.close(force: true);
          }
        }

        final menuWire = await raw(parent.requestId);
        final detailWire = await raw(child.requestId);
        expect(menuWire.containsKey('recipes'), false);
        expect(
          (menuWire['generation'] as Map)['calls'],
          inInclusiveRange(1, 2),
        );
        await File('/tmp/recare-menu-live-result.json').writeAsString(
          jsonEncode({
            'menus': menus.menus.map((m) => m.title).toList(),
            'selected': selected.title,
            'menu_generation': menuWire['generation'],
            'detail_generation': detailWire['generation'],
          }),
        );
        await File('/tmp/recare-menu-live-generated').writeAsString('done');
        for (
          var i = 0;
          i < 180 && !await File('/tmp/recare-menu-live-revoked').exists();
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await expectLater(
          client.lookupMenus(parent, now),
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
    skip: !const bool.fromEnvironment('RECARE_MENU_LIVE_TEST'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
