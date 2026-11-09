import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/recipe_repository.dart';
import '../domain/recipes.dart';

abstract class RecipeClient {
  Future<RecipeResult> recommend(RecipeRequest request, DateTime now);
  Future<RecipeResult?> lookup(RecipeRequest request, DateTime now);
  void cancel();
  void close();
}

/// Optional capability, so older injected clients keep their existing flow.
abstract class MenuRecipeClient {
  Future<RecipeMenuResult> recommendMenus(RecipeRequest request, DateTime now);
  Future<RecipeMenuResult?> lookupMenus(RecipeRequest request, DateTime now);
  Future<RecipeResult> recommendMenuDetail(
    RecipeRequest request,
    String parentRequestId,
    String menuId,
    DateTime now,
  );
  Future<RecipeResult?> lookupMenuDetail(
    RecipeRequest request,
    String parentRequestId,
    String menuId,
    DateTime now,
  );
}

class RecipeClientException implements Exception {
  const RecipeClientException(
    this.code,
    this.message, {
    this.retryable = false,
    this.retryAt,
  });
  final String code, message;
  final bool retryable;
  final DateTime? retryAt;
  @override
  String toString() => message;
}

/// Only the Supabase public project key belongs in application configuration.
/// OpenAI and service-role credentials are owned by the Edge Function.
class SupabaseRecipeClient implements RecipeClient, MenuRecipeClient {
  SupabaseRecipeClient({
    required this.repository,
    String? supabaseUrl,
    String? publishableKey,
  }) : _url =
           supabaseUrl ?? const String.fromEnvironment('RECARE_SUPABASE_URL'),
       _publicKey =
           publishableKey ??
           const String.fromEnvironment('RECARE_SUPABASE_PUBLISHABLE_KEY');

  final RecipeRepository repository;
  final String _url, _publicKey;
  final HttpClient _http = HttpClient();
  HttpClientRequest? _active;
  int _epoch = 0;
  bool _closed = false;
  bool _busy = false;

  Uri get _base {
    final uri = Uri.tryParse(_url);
    final local =
        uri != null && ['localhost', '127.0.0.1', '::1'].contains(uri.host);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && !(local && uri.scheme == 'http')) ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        !_isPublicKey(_publicKey)) {
      throw const RecipeClientException(
        'configuration',
        '추천 서버 연결이 아직 준비되지 않았어요. 저장한 레시피는 계속 볼 수 있어요.',
      );
    }
    return uri;
  }

  static bool _isPublicKey(String key) {
    if (key.startsWith('sb_publishable_') && key.length > 15) return true;
    // Legacy project anon keys are JWTs. Explicitly refuse privileged JWTs.
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  void _check(int epoch) {
    if (_closed || epoch != _epoch) {
      throw const RecipeClientException('cancelled', '추천 요청을 취소했어요.');
    }
  }

  /// Returns only this installation's registration code, never its tokens.
  Future<String> testerId(DateTime now) async {
    if (_busy) throw const RecipeClientException('in_progress', '요청을 처리 중이에요.');
    _busy = true;
    final epoch = _epoch;
    try {
      return await (() async {
        final base = _base;
        final session = await _session(base, now, epoch);
        final response = await _send(
          'POST',
          base.resolve(
            '/functions/v1/recipe-recommendations?action=registration',
          ),
          epoch,
          body: {},
          token: session.accessToken,
        );
        final id = response['registration_id'];
        if (id is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
          throw const RecipeClientException(
            'configuration',
            '등록 ID를 확인하지 못했어요.',
          );
        }
        return id;
      })().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _epoch++;
          _active?.abort();
          throw const RecipeClientException(
            'timeout',
            '등록 ID 확인이 지연되고 있어요. 다시 시도해주세요.',
          );
        },
      );
    } on FormatException {
      throw const RecipeClientException('configuration', '등록 응답을 확인하지 못했어요.');
    } on SocketException {
      throw const RecipeClientException('unavailable', '인터넷 연결을 확인해주세요.');
    } on HandshakeException {
      throw const RecipeClientException('unavailable', '서버 연결을 확인하지 못했어요.');
    } on HttpException {
      throw const RecipeClientException('unavailable', '서버 연결을 확인하지 못했어요.');
    } finally {
      _active = null;
      _busy = false;
    }
  }

  @override
  Future<RecipeResult> recommend(RecipeRequest request, DateTime now) async =>
      (await _run<RecipeResult>(
        request,
        now,
        lookupOnly: false,
        parse: (json) => RecipeResult.fromResponse(json, request, now),
      ))!;

  @override
  Future<RecipeResult?> lookup(RecipeRequest request, DateTime now) =>
      _run<RecipeResult>(
        request,
        now,
        lookupOnly: true,
        parse: (json) => RecipeResult.fromResponse(json, request, now),
      );

  @override
  Future<RecipeMenuResult> recommendMenus(
    RecipeRequest request,
    DateTime now,
  ) async => (await _menus(request, now, false))!;
  @override
  Future<RecipeMenuResult?> lookupMenus(RecipeRequest request, DateTime now) =>
      _menus(request, now, true);
  Future<RecipeMenuResult?> _menus(
    RecipeRequest request,
    DateTime now,
    bool lookup,
  ) => _run<RecipeMenuResult>(
    request,
    now,
    lookupOnly: lookup,
    extra: {'stage': 'menus'},
    parse: (json) =>
        RecipeMenuResult.fromResponse(json, request.requestId, now),
  );
  @override
  Future<RecipeResult> recommendMenuDetail(
    RecipeRequest request,
    String parentRequestId,
    String menuId,
    DateTime now,
  ) async => (await _detail(request, parentRequestId, menuId, now, false))!;
  @override
  Future<RecipeResult?> lookupMenuDetail(
    RecipeRequest request,
    String parentRequestId,
    String menuId,
    DateTime now,
  ) => _detail(request, parentRequestId, menuId, now, true);
  Future<RecipeResult?> _detail(
    RecipeRequest request,
    String parentRequestId,
    String menuId,
    DateTime now,
    bool lookup,
  ) => _run<RecipeResult>(
    request,
    now,
    lookupOnly: lookup,
    extra: {
      'stage': 'detail',
      'parent_request_id': parentRequestId,
      'menu_id': menuId,
    },
    parse: (json) {
      final result = RecipeResult.fromResponse(json, request, now);
      if (result.recipes.length > 1) {
        throw const FormatException('Expected selected detail');
      }
      return result;
    },
  );

  Future<T?> _run<T>(
    RecipeRequest request,
    DateTime now, {
    required bool lookupOnly,
    required T Function(Map<String, dynamic>) parse,
    Map<String, dynamic> extra = const {},
  }) async {
    // Validate before auth/network; a stale selection must never be sent.
    request.validate();
    final payload = lookupOnly
        ? <String, dynamic>{}
        : {...request.toJson(now), ...extra};
    final base = _base;
    if (_busy) {
      throw const RecipeClientException(
        'in_progress',
        '이전 요청을 확인하고 있어요.',
        retryable: true,
      );
    }
    _busy = true;
    final epoch = _epoch;
    try {
      final result =
          await _perform(
            base,
            request,
            payload,
            now,
            epoch,
            lookupOnly,
          ).timeout(
            const Duration(seconds: 35),
            onTimeout: () {
              _epoch++;
              _active?.abort();
              throw const RecipeClientException(
                'timeout',
                '응답을 기다리는 시간이 길어졌어요. 같은 요청의 결과를 확인해주세요.',
                retryable: true,
              );
            },
          );
      _check(epoch);
      return result == null ? null : parse(result);
    } on RecipeClientException {
      rethrow;
    } on SocketException {
      _check(epoch);
      throw const RecipeClientException(
        'offline',
        '추천에는 인터넷 연결이 필요해요.',
        retryable: true,
      );
    } on HandshakeException {
      _check(epoch);
      throw const RecipeClientException(
        'unavailable',
        '추천 서버에 안전하게 연결하지 못했어요.',
        retryable: true,
      );
    } on HttpException {
      _check(epoch);
      throw const RecipeClientException(
        'unavailable',
        '연결이 끊어졌어요. 같은 요청의 결과를 확인해주세요.',
        retryable: true,
      );
    } on FormatException {
      throw const RecipeClientException(
        'invalid_output',
        '추천 결과를 읽지 못했어요. 같은 요청의 결과를 확인해주세요.',
      );
    } on ArgumentError {
      throw const RecipeClientException(
        'invalid_output',
        '추천 결과가 재료 조건과 맞지 않아 표시하지 않았어요.',
      );
    } catch (_) {
      _check(epoch);
      throw const RecipeClientException(
        'unavailable',
        '추천을 불러오지 못했어요. 같은 요청의 결과를 확인해주세요.',
        retryable: true,
      );
    } finally {
      _active = null;
      _busy = false;
    }
  }

  Future<Map<String, dynamic>?> _perform(
    Uri base,
    RecipeRequest request,
    Map<String, dynamic> payload,
    DateTime now,
    int epoch,
    bool lookupOnly,
  ) async {
    final session = await _session(base, now, epoch);
    try {
      return await _performWithSession(
        base,
        request,
        payload,
        now,
        epoch,
        lookupOnly,
        session,
      );
    } on RecipeClientException catch (error) {
      if (error.code != 'unauthorized') rethrow;
      final refreshed = await _session(base, now, epoch, forceRefresh: true);
      try {
        return await _performWithSession(
          base,
          request,
          payload,
          now,
          epoch,
          lookupOnly,
          refreshed,
        );
      } on RecipeClientException catch (second) {
        if (second.code == 'unauthorized') {
          await repository.saveValue('recipe.auth', null);
          await repository.saveValue('recipe.issued', null);
        }
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>?> _performWithSession(
    Uri base,
    RecipeRequest request,
    Map<String, dynamic> payload,
    DateTime now,
    int epoch,
    bool lookupOnly,
    _Session session,
  ) async {
    _check(epoch);
    final endpoint = base.resolve('/functions/v1/recipe-recommendations');
    if (!lookupOnly) {
      final raw = await repository.loadValue('recipe.issued');
      _check(epoch);
      Map<String, dynamic>? issued;
      try {
        if (raw != null) issued = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        /* A missing issuance may safely be issued again server-side. */
      }
      if (issued?['request_id'] != request.requestId ||
          issued?['user_id'] != session.userId) {
        final result = await _send(
          'POST',
          endpoint.replace(queryParameters: {'action': 'issue'}),
          epoch,
          token: session.accessToken,
          body: {'request_id': request.requestId},
        );
        _check(epoch);
        if (result['request_id'] != request.requestId) {
          throw const RecipeClientException(
            'invalid_output',
            '추천 요청을 확인하지 못했어요.',
          );
        }
        await repository.saveValue(
          'recipe.issued',
          jsonEncode({
            'request_id': request.requestId,
            'user_id': session.userId,
            'expires_at': result['expires_at'],
          }),
        );
        _check(epoch);
      }
    }
    final response = await _send(
      lookupOnly ? 'GET' : 'POST',
      lookupOnly
          ? endpoint.replace(queryParameters: {'request_id': request.requestId})
          : endpoint,
      epoch,
      token: session.accessToken,
      body: lookupOnly ? null : payload,
      allowNotFound: lookupOnly,
    );
    _check(epoch);
    if (lookupOnly && response['not_found'] == true) return null;
    return response;
  }

  Future<_Session> _session(
    Uri base,
    DateTime now,
    int epoch, {
    bool forceRefresh = false,
  }) async {
    final raw = await repository.loadValue('recipe.auth');
    _check(epoch);
    _Session? previous;
    try {
      if (raw != null) {
        previous = _Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      /* Incomplete local auth cannot be used as a credential. */
    }
    if (previous != null && previous.project != base.toString()) {
      previous = null;
    }
    if (!forceRefresh &&
        previous != null &&
        previous.expiresAt.isAfter(now.add(const Duration(seconds: 30)))) {
      return previous;
    }
    Map<String, dynamic> response;
    try {
      response = await _send(
        'POST',
        base.resolve(
          previous == null
              ? '/auth/v1/signup'
              : '/auth/v1/token?grant_type=refresh_token',
        ),
        epoch,
        body: previous == null
            ? {'data': <String, dynamic>{}}
            : {'refresh_token': previous.refreshToken},
      );
    } on RecipeClientException catch (error) {
      if (error.code == 'unauthorized') {
        await repository.saveValue('recipe.auth', null);
      }
      rethrow;
    }
    _check(epoch);
    final access = response['access_token'];
    final refresh = response['refresh_token'];
    final user = response['user'];
    final seconds = response['expires_in'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        user is! Map ||
        user['id'] is! String ||
        seconds is! num ||
        seconds <= 0) {
      throw const RecipeClientException(
        'unauthorized',
        '익명 이용 연결을 확인하지 못했어요. 잠시 후 다시 시도해주세요.',
      );
    }
    final session = _Session(
      access,
      refresh,
      user['id'] as String,
      now.add(Duration(seconds: seconds.toInt())),
      base.toString(),
    );
    await repository.saveValue('recipe.auth', jsonEncode(session.toJson()));
    _check(epoch);
    return session;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    int epoch, {
    String? token,
    Map<String, dynamic>? body,
    bool allowNotFound = false,
  }) async {
    _check(epoch);
    final request = await _http.openUrl(method, uri);
    if (_closed || epoch != _epoch) request.abort();
    _check(epoch);
    _active = request;
    request.headers.set('apikey', _publicKey);
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    _check(epoch);
    final bytes = <int>[];
    await for (final chunk in response) {
      _check(epoch);
      bytes.addAll(chunk);
      if (bytes.length > 512 * 1024) {
        request.abort();
        throw const RecipeClientException(
          'invalid_output',
          '추천 결과가 너무 커서 표시하지 않았어요.',
        );
      }
    }
    _check(epoch);
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid response');
      }
      decoded = value;
    } on FormatException {
      if (response.statusCode >= 400) {
        throw _safeError(
          response.statusCode == 401 || response.statusCode == 403
              ? 'unauthorized'
              : response.statusCode == 429
              ? 'rate_limited'
              : 'unavailable',
          null,
        );
      }
      rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      if (allowNotFound &&
          response.statusCode == 404 &&
          error is Map &&
          error['code'] == 'not_found') {
        return {'not_found': true};
      }
      final code = error is Map && error['code'] is String
          ? error['code'] as String
          : response.statusCode == 401 || response.statusCode == 403
          ? 'unauthorized'
          : 'unavailable';
      DateTime? retryAt;
      if (error is Map && error['retry_at'] is String) {
        retryAt = DateTime.tryParse(error['retry_at'] as String);
      }
      throw _safeError(code, retryAt);
    }
    return decoded;
  }

  static RecipeClientException _safeError(String code, DateTime? retryAt) {
    final message = switch (code) {
      'not_enrolled' => '이 기기는 추천 테스트에 등록되지 않았어요. 상단의 테스트 등록 ID를 운영자에게 알려주세요.',
      'unauthorized' => '익명 이용 연결이 만료됐어요. 다시 연결해주세요.',
      'disabled' => '새 레시피 추천이 잠시 중지됐어요. 저장한 레시피는 볼 수 있어요.',
      'daily_limit' => '오늘 추천 횟수를 모두 사용했어요. 다음 이용 가능 시간을 확인해주세요.',
      'budget_limit' => '추천 서비스의 이용 한도에 도달했어요. 저장한 레시피를 이용해주세요.',
      'in_progress' => '요청을 처리 중이에요. 잠시 후 같은 요청의 결과를 확인해주세요.',
      'expired' => '이 추천 요청의 유효기간이 지났어요. 조건을 확인하고 새로 추천받아주세요.',
      'conflict' => '요청 조건이 달라졌어요. 조건을 확인하고 새 추천을 시작해주세요.',
      'timeout' => '처리 시간이 길어졌어요. 같은 요청의 결과를 확인해주세요.',
      'rate_limited' => '요청이 잠시 몰렸어요. 잠시 후 같은 요청을 확인해주세요.',
      'configuration' => '추천 서버 설정을 확인 중이에요. 반복 요청하지 말고 나중에 이용해주세요.',
      'invalid_request' => '선택한 재료와 추천 조건을 다시 확인해주세요.',
      'invalid_output' => '조건에 맞는 추천 결과를 확인하지 못했어요. 조건을 수정해주세요.',
      _ => '추천을 불러오지 못했어요. 잠시 후 같은 요청의 결과를 확인해주세요.',
    };
    return RecipeClientException(
      code,
      message,
      retryable: [
        'in_progress',
        'timeout',
        'rate_limited',
        'unavailable',
      ].contains(code),
      retryAt: retryAt,
    );
  }

  @override
  void cancel() {
    _epoch++;
    _active?.abort();
  }

  @override
  void close() {
    _closed = true;
    cancel();
    _http.close(force: true);
  }
}

class _Session {
  const _Session(
    this.accessToken,
    this.refreshToken,
    this.userId,
    this.expiresAt,
    this.project,
  );
  final String accessToken, refreshToken, userId, project;
  final DateTime expiresAt;
  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'project': project,
  };
  factory _Session.fromJson(Map<String, dynamic> json) => _Session(
    json['access_token'] as String,
    json['refresh_token'] as String,
    json['user_id'] as String,
    DateTime.parse(json['expires_at'] as String),
    json['project'] as String,
  );
}
