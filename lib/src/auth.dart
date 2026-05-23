/// Authentication flow for the SAIC iSmart API.
///
/// Implements the OAuth2 `password` grant used by the mobile app, including
/// SHA-1 password hashing, synthetic device-ID construction, and login-type
/// selection. All details from `src/saic_ismart_client_ng/api/base.py:login()`.
library;

import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'utils/crypto_utils.dart';

/// Supported API regions, each with its own base URI, tenant ID, and
/// `REGION` header value.
///
/// Source: `src/saic_ismart_client_ng/model.py:SaicApiConfiguration`
enum SaicRegion {
  /// European gateway — default for MG/Roewe/LDV vehicles sold in the EU.
  europe(
    baseUri: 'https://gateway-mg-eu.soimt.com/api.app/v1/',
    tenantId: '459771',
    regionHeader: 'eu',
  ),

  /// Placeholder — untested, no device available to verify.
  china(
    baseUri: 'https://gateway-mg-cn.soimt.com/api.app/v1/',
    tenantId: '459771',
    regionHeader: 'cn',
  );

  // ignore: public_member_api_docs
  const SaicRegion({
    required this.baseUri,
    required this.tenantId,
    required this.regionHeader,
  });

  /// Base URI for all API calls. Trailing slash included.
  final String baseUri;

  /// Tenant identifier sent in the `tenant-id` header on every request.
  final String tenantId;

  /// Value of the `REGION` header sent on every request.
  final String regionHeader;
}

/// Immutable configuration for a single iSmart user session.
class SaicConfig {
  /// iSmart account username — email address or phone number.
  final String username;

  /// Plaintext password. SHA-1 hashed before being sent to the API.
  final String password;

  /// API region. Defaults to [SaicRegion.europe].
  final SaicRegion region;

  /// When `true`, [username] is treated as an email and `loginType: "2"` is
  /// sent. When `false`, `loginType: "1"` is sent and [phoneCountryCode] is
  /// required. (`base.py:login()`)
  final bool usernameIsEmail;

  /// Phone country code (e.g. `"44"` for the UK). Required when
  /// [usernameIsEmail] is `false`.
  final String? phoneCountryCode;

  // ignore: public_member_api_docs
  const SaicConfig({
    required this.username,
    required this.password,
    this.region = SaicRegion.europe,
    this.usernameIsEmail = true,
    this.phoneCountryCode,
  });
}

/// Parsed response from a successful `POST /oauth/token` call.
///
/// Source: `src/saic_ismart_client_ng/api/schema.py:LoginResp`
class LoginResponse {
  /// Bearer token sent as `blade-auth` header on all subsequent requests.
  final String accessToken;

  /// Token type — always `"bearer"` in practice.
  final String tokenType;

  /// Token lifetime in seconds from the moment of issue.
  final int expiresIn;

  /// Absolute expiration time — computed as `now + expiresIn` at parse time.
  final DateTime tokenExpiration;

  /// Opaque user identifier returned by the server.
  final String userId;

  /// Username echoed back by the server.
  final String userName;

  // ignore: public_member_api_docs
  const LoginResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.tokenExpiration,
    required this.userId,
    required this.userName,
  });

  /// Parses the `data` map from a successful login JSON response.
  factory LoginResponse.fromJson(Map<String, dynamic> data) {
    final expiresIn = (data['expires_in'] as num).toInt();
    return LoginResponse(
      accessToken: data['access_token'] as String,
      tokenType: data['token_type'] as String,
      expiresIn: expiresIn,
      tokenExpiration: DateTime.now().add(Duration(seconds: expiresIn)),
      userId: data['user_id'] as String? ?? '',
      userName: data['user_name'] as String? ?? '',
    );
  }
}

/// Handles authentication against the iSmart OAuth endpoint.
///
/// Inject [httpClient] in tests to avoid real network calls.
class SaicAuth {
  final http.Client _client;

  // Hardcoded OAuth client credential — `sword:sword_secret` base64-encoded.
  // Source: `base.py:login()`
  static const _basicAuth = 'Basic c3dvcmQ6c3dvcmRfc2VjcmV0';

  // ignore: public_member_api_docs
  SaicAuth({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  /// Authenticates [config] against the iSmart API and returns a [LoginResponse].
  ///
  /// Throws [SaicAuthException] when:
  /// - The HTTP response status is 401 or 403.
  /// - The JSON `code` field is 401 or 403.
  /// - [config] has `usernameIsEmail == false` but no [SaicConfig.phoneCountryCode].
  ///
  Future<LoginResponse> login(SaicConfig config) async {
    final bodyMap = _buildFormBody(config);
    final uri = Uri.parse('${config.region.baseUri}oauth/token');
    const requestPath = '/oauth/token';
    const contentType = 'application/x-www-form-urlencoded';
    final timestampMs = DateTime.now().millisecondsSinceEpoch.toString();

    // URL-encode the form fields, then apply the standard AES-CBC pipeline.
    // userToken is empty at login time — the key formula uses '' in its place.
    final plainBody = Uri(queryParameters: bodyMap).query;
    final keyHex = deriveRequestKey(
      requestPath, config.region.tenantId, '', timestampMs, contentType,
    );
    final ivHex = deriveRequestIv(timestampMs);
    final encryptedBody = encryptBody(plainBody, keyHex, ivHex);
    final hmac = computeHmac(
      requestPath, config.region.tenantId, '', timestampMs, contentType,
      encryptedBody,
    );

    final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {
          'Content-Type': contentType,
          'Accept': 'application/json',
          'Authorization': _basicAuth,
          'tenant-id': config.region.tenantId,
          'User-Agent': 'Europe/2.1.0 (iPad; iOS 18.5; Scale/2.00)',
          'REGION': config.region.regionHeader,
          'APP-LANGUAGE-TYPE': 'en',
          'User-Type': 'app',
          'APP-SEND-DATE': timestampMs,
          'ORIGINAL-CONTENT-TYPE': contentType,
          'APP-CONTENT-ENCRYPTED': '1',
          'APP-VERIFICATION-STRING': hmac,
        },
        body: encryptedBody,
      );
    } on SocketException catch (e) {
      throw SaicNetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw SaicNetworkException(message: e.message ?? 'Request timed out');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SaicAuthException(
        code: response.statusCode,
        message: 'HTTP ${response.statusCode}',
      );
    }

    final String responseBody;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final appSendDate = response.headers['app-send-date'] ?? '';
      final originalCt =
          response.headers['original-content-type'] ?? 'application/json';
      responseBody = decryptBody(
        response.body,
        deriveResponseKey(appSendDate, originalCt),
        deriveResponseIv(appSendDate),
      );
    } else {
      responseBody = response.body;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (_) {
      throw SaicApiException(
        code: response.statusCode,
        message: 'Invalid JSON response: $responseBody',
      );
    }

    final code = json['code'];
    if (code == 401 || code == 403) {
      throw SaicAuthException(
        code: code as int,
        message: json['message'] as String? ?? 'Authentication failed',
      );
    }
    if (code != 0) {
      throw SaicApiException(
        code: code as int?,
        message: json['message'] as String? ?? 'API error',
      );
    }

    return LoginResponse.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Returns `true` if [tokenExpiration] is at or before the current time.
  static bool isTokenExpired(DateTime tokenExpiration) =>
      !DateTime.now().isBefore(tokenExpiration);

  Map<String, String> _buildFormBody(SaicConfig config) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    // 45 asterisks pad the prefix to a fixed width before appending the
    // timestamp. Source: `base.py:login()` — hardcoded asterisk string.
    final deviceId = 'simulator${'*' * 45}$ts###com.saicmotor.europecar';

    final body = <String, String>{
      'grant_type': 'password',
      'username': config.username,
      'password': sha1Hex(config.password),
      'scope': 'all',
      'deviceId': deviceId,
      'deviceType': '0',
      'language': 'EN',
    };

    if (config.usernameIsEmail) {
      body['loginType'] = '2';
    } else if (config.phoneCountryCode != null) {
      body['loginType'] = '1';
      body['countryCode'] = config.phoneCountryCode!;
    } else {
      throw const SaicAuthException(
        message: 'phoneCountryCode is required when usernameIsEmail is false',
      );
    }

    return body;
  }
}
