import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saic_ismart/src/auth.dart';
import 'package:saic_ismart/src/client.dart';
import 'package:saic_ismart/src/exceptions.dart';
import 'package:saic_ismart/src/utils/crypto_utils.dart';
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _loginBody({String token = 'test_token'}) => jsonEncode({
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

/// Wraps [plainJson] in an AES-encrypted response with the headers the client
/// needs to decrypt it.  Uses a fixed [appSendDate] so tests are deterministic.
http.Response _encryptedResponse(
  String plainJson, {
  String appSendDate = '1700000000000',
}) {
  const ct = 'application/json';
  final body = encryptBody(plainJson, deriveResponseKey(appSendDate, ct),
      deriveResponseIv(appSendDate));
  return http.Response(body, 200, headers: {
    'app-send-date': appSendDate,
    'original-content-type': ct,
  });
}

http.Response _encryptedApiResponse(dynamic data,
    {String appSendDate = '1700000000000'}) =>
    _encryptedResponse(
      jsonEncode({'code': 0, 'data': data}),
      appSendDate: appSendDate,
    );

/// Builds a [MockClient] that handles login then delegates to [onApi] for all
/// other requests.
MockClient _mockWith({
  String loginToken = 'test_token',
  required Future<http.Response> Function(http.Request) onApi,
}) {
  return MockClient((req) async {
    if (req.url.path.endsWith('/oauth/token')) {
      return _encryptedResponse(_loginBody(token: loginToken));
    }
    return onApi(req);
  });
}

const _config = SaicConfig(username: 'test@example.com', password: 'pw');

// ── Vehicle list parsing ──────────────────────────────────────────────────────

void main() {
  group('SaicClient.getVehicles — parsing', () {
    test('parses all Vehicle fields from decrypted response', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async => _encryptedApiResponse({
            'vinList': [
              {
                'vin': 'LSJA24B19NB123456',
                'modelName': 'MG ZS EV',
                'modelYear': '2023',
                'brandName': 'MG',
                'vehicleName': 'My MG',
              }
            ],
          }),
        ),
      );
      await client.login();
      final vehicles = await client.getVehicles();

      expect(vehicles, hasLength(1));
      final v = vehicles.first;
      expect(v.vin, 'LSJA24B19NB123456');
      expect(v.modelName, 'MG ZS EV');
      expect(v.modelYear, '2023');
      expect(v.brandName, 'MG');
      expect(v.vehicleName, 'My MG');
    });

    test('parses multiple vehicles', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async => _encryptedApiResponse({
            'vinList': [
              {'vin': 'VIN1', 'modelName': 'MG ZS EV'},
              {'vin': 'VIN2', 'modelName': 'MG HS PHEV'},
            ],
          }),
        ),
      );
      await client.login();
      final vehicles = await client.getVehicles();
      expect(vehicles, hasLength(2));
      expect(vehicles[1].vin, 'VIN2');
    });

    test('returns empty list when data array is empty', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
            onApi: (_) async => _encryptedApiResponse({'vinList': []})),
      );
      await client.login();
      final vehicles = await client.getVehicles();
      expect(vehicles, isEmpty);
    });

    test('tolerates absent optional fields (modelYear, brandName, vehicleName)',
        () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async => _encryptedApiResponse({
            'vinList': [
              {'vin': 'VIN1', 'modelName': 'MG ZS EV'},
            ],
          }),
        ),
      );
      await client.login();
      final v = (await client.getVehicles()).first;
      expect(v.modelYear, isNull);
      expect(v.brandName, isNull);
      expect(v.vehicleName, isNull);
    });
  });

  // ── Request headers ──────────────────────────────────────────────────────────

  group('SaicClient.getVehicles — request headers', () {
    late http.Request captured;

    setUp(() async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/oauth/token')) {
          return _encryptedResponse(_loginBody());
        }
        captured = req;
        return _encryptedApiResponse({'vinList': []});
      });
      final client = SaicClient(_config, httpClient: mock);
      await client.login();
      await client.getVehicles();
    });

    test('sends APP-CONTENT-ENCRYPTED: 1 on GET (quirk #9)', () {
      expect(captured.headers['APP-CONTENT-ENCRYPTED'], '1');
    });

    test('sends blade-auth set to access token', () {
      expect(captured.headers['blade-auth'], 'test_token');
    });

    test('sends APP-SEND-DATE as numeric millisecond string', () {
      final ts = int.tryParse(captured.headers['APP-SEND-DATE']!);
      expect(ts, isNotNull);
      expect(ts, greaterThan(0));
    });

    test('sends APP-VERIFICATION-STRING as 64-char lowercase hex', () {
      final sig = captured.headers['APP-VERIFICATION-STRING'];
      expect(sig, isNotNull);
      expect(sig, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('sends ORIGINAL-CONTENT-TYPE: application/json', () {
      expect(captured.headers['ORIGINAL-CONTENT-TYPE'], 'application/json');
    });

    test('sends Content-Type with charset suffix', () {
      expect(
          captured.headers['Content-Type'], 'application/json;charset=utf-8');
    });

    test('sends tenant-id for EU region', () {
      expect(captured.headers['tenant-id'], '459771');
    });

    test('sends REGION header for EU region', () {
      expect(captured.headers['REGION'], 'eu');
    });

    test('sends hardcoded User-Agent (quirk #3)', () {
      expect(
        captured.headers['User-Agent'],
        'Europe/2.1.0 (iPad; iOS 18.5; Scale/2.00)',
      );
    });

    test('sends User-Type: app', () {
      expect(captured.headers['User-Type'], 'app');
    });

    test('sends APP-LANGUAGE-TYPE: en', () {
      expect(captured.headers['APP-LANGUAGE-TYPE'], 'en');
    });
  });

  // ── Error handling ────────────────────────────────────────────────────────────

  group('SaicClient.getVehicles — error handling', () {
    test('throws SaicAuthException on HTTP 401', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async => http.Response('Unauthorized', 401),
        ),
      );
      await client.login();
      expect(client.getVehicles(), throwsA(isA<SaicAuthException>()));
    });

    test('SaicAuthException carries HTTP 401 code', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async => http.Response('Unauthorized', 401),
        ),
      );
      await client.login();
      expect(
        client.getVehicles(),
        throwsA(isA<SaicAuthException>().having((e) => e.code, 'code', 401)),
      );
    });

    test('throws SaicAuthException on HTTP 403', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async => http.Response('Forbidden', 403),
        ),
      );
      await client.login();
      expect(client.getVehicles(), throwsA(isA<SaicAuthException>()));
    });

    test('throws SaicAuthException on JSON code 401 in encrypted response',
        () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async =>
              _encryptedResponse('{"code":401,"message":"Unauthorized"}'),
        ),
      );
      await client.login();
      expect(client.getVehicles(), throwsA(isA<SaicAuthException>()));
    });

    test('throws SaicApiException on fatal API code 2', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async =>
              _encryptedResponse('{"code":2,"message":"Fatal"}'),
        ),
      );
      await client.login();
      expect(client.getVehicles(), throwsA(isA<SaicApiException>()));
    });

    test('throws SaicApiException on fatal API code 7', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async =>
              _encryptedResponse('{"code":7,"message":"Fatal"}'),
        ),
      );
      await client.login();
      expect(client.getVehicles(), throwsA(isA<SaicApiException>()));
    });

    test('SaicApiException carries JSON code 7', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async =>
              _encryptedResponse('{"code":7,"message":"Fatal"}'),
        ),
      );
      await client.login();
      expect(
        client.getVehicles(),
        throwsA(isA<SaicApiException>().having((e) => e.code, 'code', 7)),
      );
    });

    test('throws SaicNetworkException on SocketException', () async {
      final client = SaicClient(
        _config,
        httpClient: _mockWith(
          onApi: (_) async =>
              throw const SocketException('Connection refused'),
        ),
      );
      await client.login();
      expect(client.getVehicles(), throwsA(isA<SaicNetworkException>()));
    });
  });

  // ── session getter ────────────────────────────────────────────────────────────

  group('SaicClient.session', () {
    test('is null before login', () {
      final client = SaicClient(_config);
      expect(client.session, isNull);
    });

    test('is non-null after successful login', () async {
      final client = SaicClient(
        _config,
        httpClient: MockClient(
          (_) async => _encryptedResponse(_loginBody()),
        ),
      );
      await client.login();
      expect(client.session, isNotNull);
      expect(client.session!.accessToken, 'test_token');
      expect(client.session!.userName, 'test@example.com');
    });
  });

  // ── Request URL ───────────────────────────────────────────────────────────────

  group('SaicClient.getVehicles — request URL', () {
    test('calls correct EU endpoint', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/oauth/token')) {
          return _encryptedResponse(_loginBody());
        }
        captured = req;
        return _encryptedApiResponse({'vinList': []});
      });
      final client = SaicClient(_config, httpClient: mock);
      await client.login();
      await client.getVehicles();
      expect(
        captured?.url.toString(),
        'https://gateway-mg-eu.soimt.com/api.app/v1/vehicle/list',
      );
    });
  });
}
