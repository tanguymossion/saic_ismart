import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saic_ismart/src/auth.dart';
import 'package:saic_ismart/src/client.dart';
import 'package:saic_ismart/src/utils/crypto_utils.dart';
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _loginBody() => jsonEncode({
      'code': 0,
      'message': 'success',
      'data': {
        'access_token': 'tok',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user_id': 'u1',
        'user_name': 'test@example.com',
      },
    });

http.Response _encryptedResponse(String plain) {
  const appSendDate = '1700000000000';
  const ct = 'application/json';
  return http.Response(
    encryptBody(plain, deriveResponseKey(appSendDate, ct),
        deriveResponseIv(appSendDate)),
    200,
    headers: {'app-send-date': appSendDate, 'original-content-type': ct},
  );
}

/// Builds a [SaicClient] for [region] and returns the headers captured from
/// the first non-login outbound request.
Future<Map<String, String>> _headersFor(SaicRegion region) async {
  final captured = Completer<Map<String, String>>();

  final mock = MockClient((req) async {
    if (req.url.path.endsWith('/oauth/token')) {
      return _encryptedResponse(_loginBody());
    }
    if (!captured.isCompleted) {
      captured.complete(Map.unmodifiable(req.headers));
    }
    return _encryptedResponse(jsonEncode({'code': 0, 'data': <dynamic>[]}));
  });

  final config = SaicConfig(
    username: 'test@example.com',
    password: 'pw',
    region: region,
  );
  final client = SaicClient(config, httpClient: mock);
  await client.login();
  await client.getVehicles();
  return captured.future;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Enum values ──────────────────────────────────────────────────────────────

  group('SaicRegion.europe', () {
    test('baseUri', () {
      expect(SaicRegion.europe.baseUri,
          'https://gateway-mg-eu.soimt.com/api.app/v1/');
    });
    test('tenantId', () => expect(SaicRegion.europe.tenantId, '459771'));
    test('regionHeader', () => expect(SaicRegion.europe.regionHeader, 'eu'));
  });

  group('SaicRegion.china', () {
    test('baseUri', () {
      expect(SaicRegion.china.baseUri,
          'https://gateway-mg-cn.soimt.com/api.app/v1/');
    });
    test('tenantId', () => expect(SaicRegion.china.tenantId, '459771'));
    test('regionHeader', () => expect(SaicRegion.china.regionHeader, 'cn'));
  });

  test('SaicRegion has exactly two values', () {
    expect(SaicRegion.values.length, 2);
  });

  // ── Header propagation ───────────────────────────────────────────────────────

  group('SaicClient header propagation', () {
    test('europe client sends REGION: eu', () async {
      final h = await _headersFor(SaicRegion.europe);
      expect(h['REGION'], 'eu');
    });

    test('europe client sends tenant-id: 459771', () async {
      final h = await _headersFor(SaicRegion.europe);
      expect(h['tenant-id'], '459771');
    });

    test('china client sends REGION: cn', () async {
      final h = await _headersFor(SaicRegion.china);
      expect(h['REGION'], 'cn');
    });

    test('china client sends tenant-id: 459771', () async {
      final h = await _headersFor(SaicRegion.china);
      expect(h['tenant-id'], '459771');
    });
  });
}
