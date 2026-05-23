import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saic_ismart/src/auth.dart';
import 'package:saic_ismart/src/cache.dart';
import 'package:saic_ismart/src/client.dart';
import 'package:saic_ismart/src/exceptions.dart';
import 'package:saic_ismart/src/utils/crypto_utils.dart';
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _vin = 'LSJA24B19NB123456';
const _config = SaicConfig(username: 'test@example.com', password: 'pw');

String _loginBody({String token = 'tok'}) => jsonEncode({
      'code': 0,
      'message': 'success',
      'data': {
        'access_token': token,
        'token_type': 'bearer',
        'expires_in': 3600,
        'user_id': 'u1',
        'user_name': 'test@example.com',
      },
    });

http.Response _encryptedResponse(
  String plain, {
  String appSendDate = '1700000000000',
}) {
  const ct = 'application/json';
  return http.Response(
    encryptBody(plain, deriveResponseKey(appSendDate, ct),
        deriveResponseIv(appSendDate)),
    200,
    headers: {'app-send-date': appSendDate, 'original-content-type': ct},
  );
}

http.Response _statusResponse(int statusTime) => _encryptedResponse(
      jsonEncode({
        'code': 0,
        'data': {'statusTime': statusTime},
      }),
    );

/// Creates a fully injectable [SaicClient] with controllable time.
///
/// Returns the client, a cache (with the same clock), and a [advance]
/// function that fast-forwards the cache clock without sleeping.
Future<(SaicClient, SaicCache, void Function(Duration))> _makeClient({
  int Function()? statusTimeProvider,
  http.Response Function(http.Request)? onStatusRequest,
}) async {
  var fakeNow = DateTime(2024, 6, 1, 12);
  final cache = SaicCache(clock: () => fakeNow);

  var callCount = 0;
  final mock = MockClient((req) async {
    if (req.url.path.endsWith('/oauth/token')) {
      return _encryptedResponse(_loginBody());
    }
    if (req.url.path.endsWith('/vehicle/status')) {
      callCount++;
      if (onStatusRequest != null) return onStatusRequest(req);
      final t = statusTimeProvider?.call() ?? callCount * 100;
      return _statusResponse(t);
    }
    throw Exception('Unexpected request: ${req.url}');
  });

  final client = SaicClient(_config, httpClient: mock, cache: cache);
  await client.login();

  return (client, cache, (delta) => fakeNow = fakeNow.add(delta));
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Cache hit (cooling down) ─────────────────────────────────────────────────

  group('getVehicleStatus — cache hit (cooling down)', () {
    test('returns cached value without making an HTTP call', () async {
      final (client, _, _) = await _makeClient();

      final first = await client.getVehicleStatus(_vin); // fetches + caches
      final second = await client.getVehicleStatus(_vin); // should hit cache

      // Both calls return the same value and no second HTTP call was made.
      expect(second.statusTime, first.statusTime);
    });

    test('returns exactly the cached VehicleStatus instance', () async {
      final (client, cache, _) = await _makeClient();

      final fetched = await client.getVehicleStatus(_vin);
      expect(cache.get(_vin), equals(fetched));

      final fromCache = await client.getVehicleStatus(_vin);
      expect(fromCache, equals(fetched));
    });

    test('different VINs are cached independently', () async {
      const vin2 = 'VIN2';
      var nextTime = 100;
      final (client, _, _) = await _makeClient(
        statusTimeProvider: () => nextTime += 100,
      );

      final s1 = await client.getVehicleStatus(_vin);
      final s2 = await client.getVehicleStatus(vin2);

      expect(s1.statusTime, isNot(s2.statusTime));

      // Re-fetch within TTL — still from cache, values unchanged
      expect((await client.getVehicleStatus(_vin)).statusTime, s1.statusTime);
      expect((await client.getVehicleStatus(vin2)).statusTime, s2.statusTime);
    });
  });

  // ── Cache miss (TTL expired) ──────────────────────────────────────────────────

  group('getVehicleStatus — cache miss (TTL expired)', () {
    test('makes a new HTTP call after TTL expires', () async {
      var callCount = 0;
      final (client, _, advance) = await _makeClient(
        statusTimeProvider: () => ++callCount * 1000,
      );

      final first = await client.getVehicleStatus(_vin);
      expect(first.statusTime, 1000);

      advance(const Duration(seconds: 601)); // past 600 s default TTL

      final second = await client.getVehicleStatus(_vin);
      expect(second.statusTime, 2000); // new value from fresh HTTP call
    });

    test('updates the cache with the fresh value', () async {
      var callCount = 0;
      final (client, cache, advance) = await _makeClient(
        statusTimeProvider: () => ++callCount * 1000,
      );

      await client.getVehicleStatus(_vin); // prime cache (statusTime=1000)
      advance(const Duration(seconds: 601));
      await client.getVehicleStatus(_vin); // refresh (statusTime=2000)

      expect(cache.get(_vin)?.statusTime, 2000);
    });

    test('still within TTL at 599 s — no HTTP call made', () async {
      var callCount = 0;
      final (client, _, advance) = await _makeClient(
        statusTimeProvider: () => ++callCount,
      );

      final first = await client.getVehicleStatus(_vin);
      advance(const Duration(seconds: 599));
      final second = await client.getVehicleStatus(_vin);

      expect(second.statusTime, first.statusTime); // same cached value
    });
  });

  // ── clearCache ───────────────────────────────────────────────────────────────

  group('clearCache', () {
    test('forces a fresh HTTP call on next getVehicleStatus', () async {
      var callCount = 0;
      final (client, _, _) = await _makeClient(
        statusTimeProvider: () => ++callCount * 100,
      );

      final first = await client.getVehicleStatus(_vin);
      client.clearCache();
      final second = await client.getVehicleStatus(_vin);

      expect(second.statusTime, isNot(first.statusTime));
    });

    test('cache is cold after clearCache — isCoolingDown is false', () async {
      final (client, cache, _) = await _makeClient();
      await client.getVehicleStatus(_vin);
      client.clearCache();
      expect(cache.isCoolingDown(_vin), isFalse);
    });
  });

  // ── clearCacheFor ─────────────────────────────────────────────────────────────

  group('clearCacheFor', () {
    test('forces fresh fetch for the cleared VIN only', () async {
      const vin2 = 'VIN2';
      var callCount = 0;
      final (client, _, _) = await _makeClient(
        statusTimeProvider: () => ++callCount * 100,
      );

      final s1 = await client.getVehicleStatus(_vin); // cached
      final s2 = await client.getVehicleStatus(vin2); // cached

      client.clearCacheFor(_vin); // only clear VIN1

      final s1b = await client.getVehicleStatus(_vin); // fresh
      final s2b = await client.getVehicleStatus(vin2); // still from cache

      expect(s1b.statusTime, isNot(s1.statusTime));
      expect(s2b.statusTime, s2.statusTime);
    });
  });

  // ── isSessionActive ───────────────────────────────────────────────────────────

  group('SaicClient.isSessionActive', () {
    test('false before login', () {
      final client = SaicClient(_config);
      expect(client.isSessionActive, isFalse);
    });

    test('true after successful login', () async {
      final mock = MockClient(
        (_) async => _encryptedResponse(_loginBody()),
      );
      final client = SaicClient(_config, httpClient: mock);
      await client.login();
      expect(client.isSessionActive, isTrue);
    });
  });

  // ── SaicSessionConflictException ──────────────────────────────────────────────

  group('SaicSessionConflictException', () {
    test('thrown on 401 when an active session token is held', () async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/oauth/token')) {
          return _encryptedResponse(_loginBody());
        }
        return http.Response('Unauthorized', 401);
      });
      final client = SaicClient(_config, httpClient: mock);
      await client.login(); // sets token
      expect(
        client.getVehicleStatus(_vin),
        throwsA(isA<SaicSessionConflictException>()),
      );
    });

    test('thrown on 403 when an active session token is held', () async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/oauth/token')) {
          return _encryptedResponse(_loginBody());
        }
        return http.Response('Forbidden', 403);
      });
      final client = SaicClient(_config, httpClient: mock);
      await client.login();
      expect(
        client.getVehicleStatus(_vin),
        throwsA(isA<SaicSessionConflictException>()),
      );
    });

    test('SaicSessionConflictException is a SaicAuthException and SaicException',
        () {
      const e = SaicSessionConflictException(code: 401, message: 'x');
      expect(e, isA<SaicAuthException>());
      expect(e, isA<SaicException>());
      expect(e.code, 401);
    });
  });
}
