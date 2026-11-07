import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recare/data/inventory_repository.dart';
import 'package:recare/data/recipe_repository.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/recipes.dart';
import 'package:recare/services/recipe_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory temporary;
  late InventoryRepository inventory;
  late RecipeRepository repository;
  late HttpServer server;
  late SupabaseRecipeClient client;
  late List<String> calls;
  late List<Map<String, dynamic>> sent;
  late DateTime now;
  late RecipeRequest request;
  late Future<void> Function(HttpRequest) handler;
  final response = <String, dynamic>{
    'status': 'ok',
    'message': '',
    'recipes': [
      {
        'title': '두부 구이',
        'servings': 1,
        'minutes': 15,
        'reason': '두부를 활용해요',
        'ingredients': [
          {
            'source_id': 'i0',
            'name': '두부',
            'amount': 150000,
            'unit': 'G',
            'display_quantity': '150 g',
            'kind': 'inventory',
          },
        ],
        'steps': ['두부를 충분히 익혀요'],
        'warnings': ['재료 상태를 확인하세요'],
      },
    ],
  };
  Future<void> reply(HttpRequest req, Object body, {int status = 200}) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('recare-client-');
    inventory = await InventoryRepository.open(
      factory: databaseFactoryFfi,
      databasePath: '${temporary.path}/client.db',
    );
    repository = RecipeRepository(inventory);
    now = DateTime.now();
    request = RecipeRequest(
      requestId: '11111111-1111-4111-8111-111111111111',
      stocks: [
        RecipeStock(
          id: 'i0',
          foods: [
            Food(
              id: 'private-food-id',
              name: '두부',
              unit: FoodUnit.gram,
              total: 300000,
              expiry: now,
              price: 5000,
              created: now,
            ),
          ],
        ),
      ],
    );
    calls = [];
    sent = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = (req) async {
      calls.add('${req.method} ${req.uri.path}?${req.uri.query}');
      final body = await utf8.decoder.bind(req).join();
      if (body.isNotEmpty) sent.add(jsonDecode(body) as Map<String, dynamic>);
      if (req.uri.path == '/auth/v1/signup') {
        await reply(req, {
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_in': 3600,
          'user': {'id': 'anonymous-user'},
        });
      } else if (req.uri.queryParameters['action'] == 'registration') {
        await reply(req, {'registration_id': 'a' * 64});
      } else if (req.uri.queryParameters['action'] == 'issue') {
        await reply(req, {
          'request_id': request.requestId,
          'expires_at': now
              .add(const Duration(hours: 24))
              .toUtc()
              .toIso8601String(),
        });
      } else {
        expect(req.headers.value('authorization'), 'Bearer access-token');
        expect(req.headers.value('apikey'), 'sb_publishable_test');
        await reply(req, response);
      }
    };
    server.listen((req) async {
      try {
        await handler(req);
      } catch (_) {
        try {
          await req.response.close();
        } catch (_) {}
      }
    });
    client = SupabaseRecipeClient(
      repository: repository,
      supabaseUrl: 'http://127.0.0.1:${server.port}',
      publishableKey: 'sb_publishable_test',
    );
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
    await inventory.close();
    await temporary.delete(recursive: true);
  });
  test('registration reports offline errors without leaking raw network exceptions', () async {
    await server.close(force: true);
    await expectLater(
      client.testerId(now),
      throwsA(
        isA<RecipeClientException>().having(
          (e) => e.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });
  test(
    'stalled registration times out instead of staying busy forever',
    () async {
      handler = (req) async {
        await utf8.decoder.bind(req).join();
      };
      await expectLater(
        client.testerId(now),
        throwsA(
          isA<RecipeClientException>().having((e) => e.code, 'code', 'timeout'),
        ),
      );
    },
  );
  test('registration ID creates auth only and reuses the same installation identity', () async {
    expect(await client.testerId(now), 'a' * 64);
    expect(await client.testerId(now), 'a' * 64);
    expect(calls.length, 3);
    expect(calls.first, contains('/auth/v1/signup'));
    expect(
      calls.skip(1).every((v) => v.contains('action=registration')),
      isTrue,
    );
  });
  test('authenticates, issues and validates generation without sending private stock fields', () async {
    final result = await client.recommend(request, now);
    expect(result.recipes.single.title, '두부 구이');
    expect(result.recipes.single.ingredients.single.foodIds, [
      'private-food-id',
    ]);
    expect(calls, [
      'POST /auth/v1/signup?',
      'POST /functions/v1/recipe-recommendations?action=issue',
      'POST /functions/v1/recipe-recommendations?',
    ]);
    final payload = sent.last;
    expect(payload['request_id'], request.requestId);
    final encoded = jsonEncode(payload);
    expect(encoded, isNot(contains('private-food-id')));
    expect(encoded, isNot(contains('price')));
    expect(encoded, isNot(contains('created')));
    expect(payload['ingredients'][0]['amount'], 300000);
  });
  test('lookup after midnight retrieves the original snapshot without a new generation', () async {
    now = DateTime(2026, 11, 4, 23, 59);
    request = RecipeRequest(
      requestId: request.requestId,
      stocks: [
        RecipeStock(
          id: 'i0',
          foods: [
            Food(
              id: 'private-food-id',
              name: '두부',
              unit: FoodUnit.gram,
              total: 300000,
              expiry: now,
              price: 5000,
              created: now,
            ),
          ],
        ),
      ],
    );
    await client.recommend(request, now);
    final result = await client.lookup(
      request,
      now.add(const Duration(minutes: 2)),
    );
    expect(result!.recipes.single.title, '두부 구이');
    expect(
      calls
          .where((c) => c == 'POST /functions/v1/recipe-recommendations?')
          .length,
      1,
    );
    expect(
      calls.last,
      startsWith('GET /functions/v1/recipe-recommendations?request_id='),
    );
  });
  test(
    'reopened client reuses anonymous session and same job issuance',
    () async {
      await client.recommend(request, now);
      client.close();
      client = SupabaseRecipeClient(
        repository: repository,
        supabaseUrl: 'http://127.0.0.1:${server.port}',
        publishableKey: 'sb_publishable_test',
      );
      await client.recommend(request, now);
      expect(calls.where((c) => c.startsWith('POST /auth')).length, 1);
      expect(calls.where((c) => c.contains('action=issue')).length, 1);
    },
  );
  test('lookup never creates a job or generation', () async {
    final original = handler;
    handler = (req) async {
      if (req.method == 'GET') {
        calls.add('lookup');
        await reply(req, {
          'error': {'code': 'not_found', 'message': '없음', 'retryable': false},
        }, status: 404);
      } else {
        await original(req);
      }
    };
    expect(await client.lookup(request, now), isNull);
    expect(calls, ['POST /auth/v1/signup?', 'lookup']);
  });
  test('quota errors expose safe Korean guidance and retry time', () async {
    final original = handler;
    handler = (req) async {
      if (req.uri.path.contains('recipe') && req.uri.query.isEmpty) {
        await reply(req, {
          'error': {
            'code': 'daily_limit',
            'message': 'raw sensitive error',
            'retryable': false,
            'retry_at': '2026-11-06T15:00:00Z',
          },
        }, status: 429);
      } else {
        await original(req);
      }
    };
    await expectLater(
      client.recommend(request, now),
      throwsA(
        isA<RecipeClientException>()
            .having((e) => e.code, 'code', 'daily_limit')
            .having(
              (e) => e.message.contains('raw sensitive'),
              'sanitized',
              false,
            )
            .having((e) => e.retryAt, 'retry', DateTime.utc(2026, 11, 6, 15)),
      ),
    );
  });
  test('missing config fails locally without any network request', () async {
    client.close();
    client = SupabaseRecipeClient(
      repository: repository,
      supabaseUrl: '',
      publishableKey: '',
    );
    await expectLater(
      client.recommend(request, now),
      throwsA(
        isA<RecipeClientException>().having(
          (e) => e.code,
          'code',
          'configuration',
        ),
      ),
    );
    expect(calls, isEmpty);
  });
  test(
    'server-only credentials and nonlocal insecure URLs are rejected',
    () async {
      for (final pair in [
        ('https://project.supabase.co', 'sb_secret_forbidden'),
        ('http://project.supabase.co', 'sb_publishable_test'),
      ]) {
        final rejected = SupabaseRecipeClient(
          repository: repository,
          supabaseUrl: pair.$1,
          publishableKey: pair.$2,
        );
        await expectLater(
          rejected.recommend(request, now),
          throwsA(isA<RecipeClientException>()),
        );
        rejected.close();
      }
      expect(calls, isEmpty);
    },
  );
  test(
    'refreshes a rejected access token once without changing job ID',
    () async {
      await repository.saveValue(
        'recipe.auth',
        jsonEncode({
          'access_token': 'rejected-token',
          'refresh_token': 'refresh-token',
          'user_id': 'anonymous-user',
          'expires_at': now
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          'project': 'http://127.0.0.1:${server.port}',
        }),
      );
      final original = handler;
      var refreshes = 0;
      handler = (req) async {
        if (req.uri.path == '/auth/v1/token') {
          refreshes++;
          final body = jsonDecode(await utf8.decoder.bind(req).join());
          expect(body['refresh_token'], 'refresh-token');
          await reply(req, {
            'access_token': 'access-token',
            'refresh_token': 'new-refresh-token',
            'expires_in': 3600,
            'user': {'id': 'anonymous-user'},
          });
        } else if (req.headers.value('authorization') ==
            'Bearer rejected-token') {
          await reply(req, {
            'error': {
              'code': 'unauthorized',
              'message': 'expired token',
              'retryable': false,
            },
          }, status: 401);
        } else {
          await original(req);
        }
      };
      final result = await client.recommend(request, now);
      expect(result.requestId, request.requestId);
      expect(refreshes, 1);
      expect(sent.last['request_id'], request.requestId);
    },
  );
  test(
    'non-JSON upstream failures remain retryable without leaking response text',
    () async {
      final original = handler;
      handler = (req) async {
        if (req.uri.path.contains('recipe') && req.uri.query.isEmpty) {
          req.response.statusCode = 503;
          req.response.write('<html>private infrastructure diagnostic</html>');
          await req.response.close();
        } else {
          await original(req);
        }
      };
      await expectLater(
        client.recommend(request, now),
        throwsA(
          isA<RecipeClientException>()
              .having((e) => e.code, 'code', 'unavailable')
              .having((e) => e.retryable, 'retryable', true)
              .having((e) => e.message.contains('private'), 'sanitized', false),
        ),
      );
    },
  );
  test(
    'cancel aborts a running response and does not return late recipes',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final original = handler;
      handler = (req) async {
        if (req.uri.path.contains('recipe') && req.uri.query.isEmpty) {
          started.complete();
          await release.future;
          await reply(req, response);
        } else {
          await original(req);
        }
      };
      final future = client.recommend(request, now);
      final assertion = expectLater(
        future,
        throwsA(
          isA<RecipeClientException>().having(
            (e) => e.code,
            'code',
            'cancelled',
          ),
        ),
      );
      await started.future;
      client.cancel();
      release.complete();
      await assertion;
    },
  );
}
