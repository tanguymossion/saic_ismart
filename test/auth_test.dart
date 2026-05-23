import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saic_ismart/src/auth.dart';
import 'package:saic_ismart/src/exceptions.dart';
import 'package:saic_ismart/src/utils/crypto_utils.dart';
import 'package:test/test.dart';

// Minimal successful login payload matching LoginResp schema (section 1).
String _successBody({
  String accessToken = 'tok_abc123',
  String tokenType = 'bearer',
  int expiresIn = 3600,
  String userId = 'user-001',
  String userName = 'test@example.com',
}) =>
    jsonEncode({
      'code': 0,
      'message': 'success',
      'data': {
        'access_token': accessToken,
        'token_type': tokenType,
        'expires_in': expiresIn,
        'user_id': userId,
        'user_name': userName,
      },
    });

/// Returns an AES-encrypted 200 response for [plain], with the headers the
/// client needs to decrypt it.
http.Response _encryptedLoginResponse(String plain) {
  const appSendDate = '1700000000000';
  const ct = 'application/json';
  return http.Response(
    encryptBody(plain, deriveResponseKey(appSendDate, ct),
        deriveResponseIv(appSendDate)),
    200,
    headers: {'app-send-date': appSendDate, 'original-content-type': ct},
  );
}

void main() {
  const emailConfig = SaicConfig(
    username: 'test@example.com',
    password: 'hunter2',
  );

  const phoneConfig = SaicConfig(
    username: '+447700900000',
    password: 'hunter2',
    usernameIsEmail: false,
    phoneCountryCode: '44',
  );

  // ── LoginResponse parsing ──────────────────────────────────────────────────

  group('LoginResponse.fromJson', () {
    test('parses all fields correctly', () async {
      final client = MockClient(
        (_) async => _encryptedLoginResponse(_successBody()),
      );
      final response = await SaicAuth(httpClient: client).login(emailConfig);

      expect(response.accessToken, 'tok_abc123');
      expect(response.tokenType, 'bearer');
      expect(response.expiresIn, 3600);
      expect(response.userId, 'user-001');
      expect(response.userName, 'test@example.com');
    });

    test('sets tokenExpiration approximately expiresIn seconds from now', () async {
      final before = DateTime.now();
      final client = MockClient(
        (_) async => _encryptedLoginResponse(_successBody(expiresIn: 7200)),
      );
      final response = await SaicAuth(httpClient: client).login(emailConfig);
      final after = DateTime.now();

      expect(
        response.tokenExpiration.isAfter(before.add(const Duration(seconds: 7199))),
        isTrue,
      );
      expect(
        response.tokenExpiration.isBefore(after.add(const Duration(seconds: 7201))),
        isTrue,
      );
    });
  });

  // ── Request construction ───────────────────────────────────────────────────

  group('SaicAuth.login request', () {
    late http.Request captured;
    // Decrypted form fields — populated in setUp after decrypting the body.
    late Map<String, String> capturedBodyParams;

    setUp(() async {
      final client = MockClient((req) async {
        captured = req;
        return _encryptedLoginResponse(_successBody());
      });
      await SaicAuth(httpClient: client).login(emailConfig);

      // Decrypt using request-side key derivation (userToken = '' at login time).
      final ts = captured.headers['APP-SEND-DATE']!;
      final keyHex = deriveRequestKey(
        '/oauth/token', '459771', '', ts, 'application/x-www-form-urlencoded',
      );
      final plain = decryptBody(captured.body, keyHex, deriveRequestIv(ts));
      capturedBodyParams = Uri.splitQueryString(plain);
    });

    test('sends to correct EU endpoint', () {
      expect(
        captured.url.toString(),
        'https://gateway-mg-eu.soimt.com/api.app/v1/oauth/token',
      );
    });

    test('sends hardcoded Authorization header', () {
      expect(captured.headers['Authorization'], 'Basic c3dvcmQ6c3dvcmRfc2VjcmV0');
    });

    test('sends Content-Type application/x-www-form-urlencoded', () {
      expect(captured.headers['Content-Type'], 'application/x-www-form-urlencoded');
    });

    test('sends tenant-id for the configured region', () {
      expect(captured.headers['tenant-id'], '459771');
    });

    test('sends User-Agent matching the mobile app string', () {
      expect(
        captured.headers['User-Agent'],
        'Europe/2.1.0 (iPad; iOS 18.5; Scale/2.00)',
      );
    });

    test('sends REGION: eu for EU config', () {
      expect(captured.headers['REGION'], 'eu');
    });

    test('sends APP-LANGUAGE-TYPE: en', () {
      expect(captured.headers['APP-LANGUAGE-TYPE'], 'en');
    });

    test('sends User-Type: app', () {
      expect(captured.headers['User-Type'], 'app');
    });

    test('sends APP-SEND-DATE as numeric millisecond string', () {
      final ts = int.tryParse(captured.headers['APP-SEND-DATE']!);
      expect(ts, isNotNull);
      expect(ts, greaterThan(0));
    });

    test('sends ORIGINAL-CONTENT-TYPE: application/x-www-form-urlencoded', () {
      expect(captured.headers['ORIGINAL-CONTENT-TYPE'], 'application/x-www-form-urlencoded');
    });

    test('sends APP-CONTENT-ENCRYPTED: 1', () {
      expect(captured.headers['APP-CONTENT-ENCRYPTED'], '1');
    });

    test('sends APP-VERIFICATION-STRING as 64-char lowercase hex', () {
      final sig = captured.headers['APP-VERIFICATION-STRING'];
      expect(sig, isNotNull);
      expect(sig, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('sends loginType 2 for email login', () {
      expect(capturedBodyParams['loginType'], '2');
    });

    test('sends grant_type password and scope all', () {
      expect(capturedBodyParams['grant_type'], 'password');
      expect(capturedBodyParams['scope'], 'all');
    });

    test('sends SHA-1 hashed password, not plaintext', () {
      // SHA-1("hunter2") = f3bbbd66a63d4bf1747940578ec3d0103530e21d
      expect(capturedBodyParams['password'], 'f3bbbd66a63d4bf1747940578ec3d0103530e21d');
      expect(capturedBodyParams['password'], isNot('hunter2'));
    });

    test('sends deviceId matching expected pattern', () {
      final deviceId = capturedBodyParams['deviceId']!;
      expect(deviceId, startsWith('simulator${'*' * 45}'));
      expect(deviceId, endsWith('###com.saicmotor.europecar'));
    });
  });

  group('SaicAuth.login phone login', () {
    test('sends loginType 1 and countryCode for phone config', () async {
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return _encryptedLoginResponse(_successBody());
      });
      await SaicAuth(httpClient: client).login(phoneConfig);
      final req = captured!;
      final ts = req.headers['APP-SEND-DATE']!;
      final keyHex = deriveRequestKey(
        '/oauth/token', '459771', '', ts, 'application/x-www-form-urlencoded',
      );
      final plain = decryptBody(req.body, keyHex, deriveRequestIv(ts));
      final params = Uri.splitQueryString(plain);
      expect(params['loginType'], '1');
      expect(params['countryCode'], '44');
    });
  });

  // ── Error handling ─────────────────────────────────────────────────────────

  group('SaicAuth.login error handling', () {
    test('throws SaicAuthException on HTTP 401', () async {
      // Non-2xx: decryption is skipped, body is not read.
      final client = MockClient((_) async => http.Response('Unauthorized', 401));
      expect(
        () => SaicAuth(httpClient: client).login(emailConfig),
        throwsA(isA<SaicAuthException>()),
      );
    });

    test('throws SaicAuthException on HTTP 403', () async {
      final client = MockClient((_) async => http.Response('Forbidden', 403));
      expect(
        () => SaicAuth(httpClient: client).login(emailConfig),
        throwsA(isA<SaicAuthException>()),
      );
    });

    test('throws SaicAuthException on JSON code 401', () async {
      final client = MockClient((_) async => _encryptedLoginResponse(
            '{"code":401,"message":"Unauthorized","data":null}',
          ));
      expect(
        () => SaicAuth(httpClient: client).login(emailConfig),
        throwsA(isA<SaicAuthException>()),
      );
    });

    test('throws SaicAuthException on JSON code 403', () async {
      final client = MockClient((_) async => _encryptedLoginResponse(
            '{"code":403,"message":"Forbidden","data":null}',
          ));
      expect(
        () => SaicAuth(httpClient: client).login(emailConfig),
        throwsA(isA<SaicAuthException>()),
      );
    });

    test('throws SaicApiException on other non-zero JSON code', () async {
      final client = MockClient((_) async => _encryptedLoginResponse(
            '{"code":7,"message":"Fatal error"}',
          ));
      expect(
        () => SaicAuth(httpClient: client).login(emailConfig),
        throwsA(isA<SaicApiException>()),
      );
    });

    test('throws SaicAuthException when phone config has no country code', () {
      const bad = SaicConfig(
        username: '+447700900000',
        password: 'pw',
        usernameIsEmail: false,
        // phoneCountryCode intentionally omitted
      );
      // Exception is thrown before the HTTP call; mock response is irrelevant.
      final client = MockClient((_) async => http.Response('{}', 200));
      expect(
        () => SaicAuth(httpClient: client).login(bad),
        throwsA(isA<SaicAuthException>()),
      );
    });

    test('SaicAuthException carries HTTP 401 code', () async {
      final client =
          MockClient((_) async => http.Response('Unauthorized', 401));
      expect(
        () => SaicAuth(httpClient: client).login(emailConfig),
        throwsA(isA<SaicAuthException>().having((e) => e.code, 'code', 401)),
      );
    });

    test('SaicApiException carries JSON code 7', () async {
      final client = MockClient((_) async => _encryptedLoginResponse(
            '{"code":7,"message":"Fatal error"}',
          ));
      expect(
        () => SaicAuth(httpClient: client).login(emailConfig),
        throwsA(isA<SaicApiException>().having((e) => e.code, 'code', 7)),
      );
    });

    test('throws SaicNetworkException on SocketException', () {
      final client = MockClient(
          (_) async => throw const SocketException('Connection refused'));
      expect(
        () => SaicAuth(httpClient: client).login(emailConfig),
        throwsA(isA<SaicNetworkException>()),
      );
    });
  });

  // ── Token expiration ───────────────────────────────────────────────────────

  group('SaicAuth.isTokenExpired', () {
    test('returns true when expiration is in the past', () {
      expect(
        SaicAuth.isTokenExpired(
          DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('returns false when expiration is in the future', () {
      expect(
        SaicAuth.isTokenExpired(
          DateTime.now().add(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });

    test('returns true when expiration is exactly now', () {
      // DateTime.now() called twice; subtract 1µs to ensure "now" passes.
      final past = DateTime.now().subtract(const Duration(microseconds: 1));
      expect(SaicAuth.isTokenExpired(past), isTrue);
    });
  });
}
