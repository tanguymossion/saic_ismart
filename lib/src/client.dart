/// HTTP client for the SAIC iSmart connected-vehicle API.
///
/// Handles AES-CBC request/response encryption, HMAC-SHA-256 request signing,
/// standard header injection, and response-code error handling for all
/// API endpoints.
///
/// Source: `net/crypto.py`, `net/httpx/__init__.py`, `api/base.py`
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth.dart';
import 'exceptions.dart';
import 'models/vehicle.dart';
import 'utils/crypto_utils.dart';

// ── Internal HTTP layer ───────────────────────────────────────────────────────

/// Handles the AES-128-CBC + HMAC-SHA-256 pipeline for every API request.
///
/// All standard headers (section 2 of TECHNICAL_REFERENCE.md) are set here.
/// Callers use [get] and [post]; they never construct headers directly.
class _SaicHttpClient {
  /// Underlying HTTP client — inject a [http.MockClient] in tests.
  final http.Client rawClient;
  final SaicRegion _region;

  /// Bearer token sent in `blade-auth`. Empty until [SaicClient.login] succeeds.
  String userToken = '';

  _SaicHttpClient(this.rawClient, this._region);

  /// Executes a GET request at [path] (relative, leading `/` optional).
  ///
  /// No body encryption is performed, but `APP-CONTENT-ENCRYPTED: 1` is still
  /// set on every request (quirk #9 — TECHNICAL_REFERENCE.md §8).
  /// [params] are appended as query parameters; the full path + query string
  /// is used for key derivation (quirk #10).
  Future<dynamic> get(String path, {Map<String, String>? params}) async {
    final uri = _buildUri(path, params);
    final requestPath = _requestPathFromUri(uri);
    final timestampMs = DateTime.now().millisecondsSinceEpoch.toString();

    final headers = _buildHeaders(
      requestPath: requestPath,
      timestampMs: timestampMs,
      contentType: _kJson,
      encryptedBody: '', // GET: no body; HMAC still computed over empty string
    );

    final response = await rawClient.get(uri, headers: headers);
    return _parseResponse(response);
  }

  /// Executes a POST request at [path] with AES-encrypted [jsonBody].
  Future<dynamic> post(
    String path,
    String jsonBody, {
    Map<String, String>? params,
  }) async {
    final uri = _buildUri(path, params);
    final requestPath = _requestPathFromUri(uri);
    final timestampMs = DateTime.now().millisecondsSinceEpoch.toString();

    final keyHex = deriveRequestKey(
      requestPath,
      _region.tenantId,
      userToken,
      timestampMs,
      _kJson,
    );
    final ivHex = deriveRequestIv(timestampMs);
    final encryptedBody = encryptBody(jsonBody, keyHex, ivHex);

    final headers = _buildHeaders(
      requestPath: requestPath,
      timestampMs: timestampMs,
      contentType: _kJson,
      encryptedBody: encryptedBody,
    );

    final response = await rawClient.post(
      uri,
      headers: headers,
      body: encryptedBody,
    );
    return _parseResponse(response);
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  static const _kJson = 'application/json';

  /// Builds the URI for [path] relative to the region base URI.
  Uri _buildUri(String path, Map<String, String>? params) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    var uri = Uri.parse('${_region.baseUri}$normalizedPath');
    if (params != null && params.isNotEmpty) {
      uri = uri.replace(queryParameters: params);
    }
    return uri;
  }

  /// Derives the request_path used in key/HMAC derivation from a constructed
  /// URI. Mirrors Python's `str(url).replace(base_uri, "/")` (quirk #10).
  String _requestPathFromUri(Uri uri) {
    final fullUrl = uri.toString();
    final stripped = fullUrl.replaceFirst(_region.baseUri, '');
    return '/$stripped';
  }

  /// Builds the standard headers applied to every request.
  ///
  /// Source: `net/crypto.py:encrypt_request()` — header list in
  /// TECHNICAL_REFERENCE.md §2.
  Map<String, String> _buildHeaders({
    required String requestPath,
    required String timestampMs,
    required String contentType,
    required String encryptedBody,
  }) {
    final hmac = computeHmac(
      requestPath,
      _region.tenantId,
      userToken,
      timestampMs,
      contentType,
      encryptedBody,
    );

    return {
      'User-Agent': 'Europe/2.1.0 (iPad; iOS 18.5; Scale/2.00)',
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
      'Content-Type': '$contentType;charset=utf-8',
      'ORIGINAL-CONTENT-TYPE': contentType,
      'REGION': _region.regionHeader,
      'APP-SEND-DATE': timestampMs,
      'APP-CONTENT-ENCRYPTED': '1',
      'tenant-id': _region.tenantId,
      'User-Type': 'app',
      'APP-LANGUAGE-TYPE': 'en',
      'APP-VERIFICATION-STRING': hmac,
      if (userToken.isNotEmpty) 'blade-auth': userToken,
    };
  }

  /// Decrypts and parses an API response, throwing on any error condition.
  ///
  /// - HTTP 401/403 → [SaicAuthException] (body not decrypted, quirk #5).
  /// - JSON code 401/403 → [SaicAuthException].
  /// - JSON code 2/3/7 → [SaicApiException] (fatal, no retry).
  /// - Any other non-zero code → [SaicApiException].
  /// - Returns the `data` field of a successful (code == 0) response.
  ///
  /// Source: `base.py:__deserialize()`, `net/httpx/__init__.py:decrypt_httpx_response()`
  dynamic _parseResponse(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SaicAuthException(
        statusCode: response.statusCode,
        message: 'HTTP ${response.statusCode}',
      );
    }

    final String body;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Decrypt using key/IV derived from response headers (section 3).
      final appSendDate = response.headers['app-send-date'] ?? '';
      final originalCt =
          response.headers['original-content-type'] ?? _kJson;
      final keyHex = deriveResponseKey(appSendDate, originalCt);
      final ivHex = deriveResponseIv(appSendDate);
      body = decryptBody(response.body, keyHex, ivHex);
    } else {
      body = response.body;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw SaicApiException(
        statusCode: response.statusCode,
        message: 'Non-JSON response: $body',
      );
    }

    final code = json['code'];
    if (code == 401 || code == 403) {
      throw SaicAuthException(
        statusCode: code as int,
        message: json['message'] as String? ?? 'Auth error',
      );
    }
    if (code == 2 || code == 3 || code == 7) {
      throw SaicApiException(
        statusCode: code as int,
        message: json['message'] as String? ?? 'Fatal API error',
      );
    }
    if (code != 0) {
      throw SaicApiException(
        statusCode: code as int? ?? -1,
        message: json['message'] as String? ?? 'API error',
      );
    }

    return json['data'];
  }
}

// ── Public API client ─────────────────────────────────────────────────────────

/// Entry point for interacting with the iSmart connected-vehicle API.
///
/// ```dart
/// final client = SaicClient(
///   SaicConfig(username: 'user@example.com', password: 's3cr3t'),
/// );
/// await client.login();
/// final vehicles = await client.getVehicles();
/// ```
///
/// Inject [httpClient] to use a mock in tests.
class SaicClient {
  final SaicConfig _config;
  final _SaicHttpClient _http;
  LoginResponse? _session;

  // ignore: public_member_api_docs
  SaicClient(SaicConfig config, {http.Client? httpClient})
      : _config = config,
        _http = _SaicHttpClient(
          httpClient ?? http.Client(),
          config.region,
        );

  /// Authenticates and stores the session token.
  ///
  /// Must be called before any endpoint method. There is no automatic
  /// token refresh — call [login] again when [LoginResponse.tokenExpiration]
  /// is past (TECHNICAL_REFERENCE.md §1, quirk #13).
  Future<void> login() async {
    _session = await SaicAuth(httpClient: _http.rawClient).login(_config);
    _http.userToken = _session!.accessToken;
  }

  /// Returns all vehicles linked to the authenticated account.
  ///
  /// Endpoint: `GET /vehicle/list` — no query parameters.
  /// Source: `api/vehicle/__init__.py:vehicle_list()`
  Future<List<Vehicle>> getVehicles() async {
    final data = await _http.get('/vehicle/list') as List<dynamic>;
    return data
        .map((e) => Vehicle.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
