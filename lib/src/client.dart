/// HTTP client for the SAIC iSmart connected-vehicle API.
///
/// Handles AES-CBC request/response encryption, HMAC-SHA-256 request signing,
/// standard header injection, and response-code error handling for all
/// API endpoints.
///
/// Source: `net/crypto.py`, `net/httpx/__init__.py`, `api/base.py`
library;

import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'auth.dart';
import 'cache.dart';
import 'exceptions.dart';
import 'models/vehicle.dart';
import 'models/vehicle_status.dart';
import 'utils/crypto_utils.dart';

// ── Event-id retry signal ─────────────────────────────────────────────────────

/// Thrown by [_SaicHttpClient._parseResponse] when the server returns code 0
/// with no `data` field and an `event-id` response header, indicating the
/// request is being processed asynchronously (TECHNICAL_REFERENCE.md §4).
class _SaicEventIdRetryException implements Exception {
  final String eventId;
  const _SaicEventIdRetryException(this.eventId);
}

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
  /// [eventId] is sent as `event-id` header; defaults to `'0'` for the
  /// initial request in the event-id polling pattern (TECHNICAL_REFERENCE.md §4).
  Future<dynamic> get(
    String path, {
    Map<String, String>? params,
    String eventId = '0',
  }) async {
    final uri = _buildUri(path, params);
    final requestPath = _requestPathFromUri(uri);
    final timestampMs = DateTime.now().millisecondsSinceEpoch.toString();

    final headers = _buildHeaders(
      requestPath: requestPath,
      timestampMs: timestampMs,
      contentType: _kJson,
      encryptedBody: '', // GET: no body; HMAC still computed over empty string
    );
    headers['event-id'] = eventId;

    try {
      final response = await rawClient.get(uri, headers: headers);
      return _parseResponse(response);
    } on SocketException catch (e) {
      throw SaicNetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw SaicNetworkException(message: e.message ?? 'Request timed out');
    }
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

    try {
      final response = await rawClient.post(
        uri,
        headers: headers,
        body: encryptedBody,
      );
      return _parseResponse(response);
    } on SocketException catch (e) {
      throw SaicNetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw SaicNetworkException(message: e.message ?? 'Request timed out');
    }
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
  /// - HTTP 401/403 with an active session → [SaicSessionConflictException].
  /// - HTTP 401/403 without a session → [SaicAuthException].
  /// - JSON code 401/403 → [SaicAuthException].
  /// - JSON code 2/3/7 → [SaicApiException] (fatal, no retry).
  /// - Any other non-zero code → [SaicApiException].
  /// - code 0 with no `data` key + `event-id` response header →
  ///   [_SaicEventIdRetryException] (caller must retry with the new event-id).
  /// - Returns the `data` field of a successful (code == 0) response.
  ///
  /// Source: `base.py:__deserialize()`, `net/httpx/__init__.py:decrypt_httpx_response()`
  dynamic _parseResponse(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      // A 401/403 while holding an active token means another client has
      // taken the session — surface this as a conflict, not a plain auth error.
      if (userToken.isNotEmpty) {
        throw SaicSessionConflictException(
          code: response.statusCode,
          message:
              'Session conflict — another client may have authenticated with '
              'the same credentials (TECHNICAL_REFERENCE.md §4)',
        );
      }
      throw SaicAuthException(
        code: response.statusCode,
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
        code: response.statusCode,
        message: 'Non-JSON response: $body',
      );
    }

    final code = json['code'];
    if (code == 401 || code == 403) {
      throw SaicAuthException(
        code: code as int,
        message: json['message'] as String? ?? 'Auth error',
      );
    }
    if (code == 2 || code == 3 || code == 7) {
      throw SaicApiException(
        code: code as int,
        message: json['message'] as String? ?? 'Fatal API error',
      );
    }
    if (code != 0) {
      throw SaicApiException(
        code: code as int?,
        message: json['message'] as String? ?? 'API error',
      );
    }

    // Detect event-id retry: server returns code 0 with no data field while
    // processing the request asynchronously (TECHNICAL_REFERENCE.md §4).
    if (!json.containsKey('data') || json['data'] == null) {
      final eventIdHeader = response.headers['event-id'];
      if (eventIdHeader != null) {
        throw _SaicEventIdRetryException(eventIdHeader);
      }
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
/// final status  = await client.getVehicleStatus(vehicles.first.vin);
/// ```
///
/// Inject [httpClient] to use a [http.MockClient] in tests.
/// Inject [cache] to override the default 600 s cooldown TTL.
class SaicClient {
  final SaicConfig _config;
  final _SaicHttpClient _http;
  final SaicCache _cache;
  final Duration _statusRetryDelay;
  final Duration _statusRetryTimeout;
  LoginResponse? _session;

  // ignore: public_member_api_docs
  SaicClient(
    SaicConfig config, {
    http.Client? httpClient,
    SaicCache? cache,
    Duration statusRetryDelay = const Duration(seconds: 3),
    Duration statusRetryTimeout = const Duration(seconds: 30),
  })  : _config = config,
        _http = _SaicHttpClient(
          httpClient ?? http.Client(),
          config.region,
        ),
        _cache = cache ?? SaicCache(),
        _statusRetryDelay = statusRetryDelay,
        _statusRetryTimeout = statusRetryTimeout;

  /// The [LoginResponse] from the most recent successful [login] call, or
  /// `null` if [login] has not been called yet.
  LoginResponse? get session => _session;

  /// `true` if [login] has been called successfully and the token has not
  /// yet expired.
  bool get isSessionActive {
    final s = _session;
    return s != null && !SaicAuth.isTokenExpired(s.tokenExpiration);
  }

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
    final data = await _http.get('/vehicle/list') as Map<String, dynamic>;
    final vinList = (data['vinList'] as List<dynamic>?) ?? [];
    return vinList
        .map((e) => Vehicle.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns a real-time status snapshot for [vin], serving from the cache
  /// when the last fetch was less than the configured TTL ago.
  ///
  /// **Cache behaviour:** if [SaicCache.isCoolingDown] is true for [vin],
  /// the cached [VehicleStatus] is returned immediately and no HTTP call is
  /// made. Otherwise a fresh value is fetched, stored in the cache, and
  /// returned.
  ///
  /// The [vin] is hashed with SHA-256 before being sent — the raw VIN is never
  /// transmitted (TECHNICAL_REFERENCE.md §2 — VIN hashing).
  ///
  /// `vehStatusReqType=2` is always hardcoded (quirk #11).
  ///
  /// The server processes this request asynchronously: the first response
  /// carries `code 0` with no `data` field and an `event-id` header.
  /// The client retries with that event-id until `data` arrives, timing out
  /// after 30 s (TECHNICAL_REFERENCE.md §4 — event-id retry pattern).
  ///
  /// Endpoint: `GET /vehicle/status?vin={sha256Hex(vin)}&vehStatusReqType=2`
  /// Source: `api/vehicle/__init__.py:get_vehicle_status()`
  Future<VehicleStatus> getVehicleStatus(String vin) async {
    if (_cache.isCoolingDown(vin)) {
      return _cache.get(vin)!; // guaranteed non-null when isCoolingDown
    }

    var eventId = '0';
    final deadline = DateTime.now().add(_statusRetryTimeout);

    while (true) {
      try {
        final rawData = await _http.get(
          '/vehicle/status',
          params: {'vin': sha256Hex(vin), 'vehStatusReqType': '2'},
          eventId: eventId,
        );
        final data = rawData as Map<String, dynamic>;
        final status = VehicleStatus.fromJson(data);
        _cache.set(vin, status);
        return status;
      } on _SaicEventIdRetryException catch (e) {
        if (DateTime.now().isAfter(deadline)) {
          throw SaicTimeoutException(
            message: 'getVehicleStatus timed out after 30 s '
                '(event-id: ${e.eventId})',
          );
        }
        eventId = e.eventId;
        await Future.delayed(_statusRetryDelay);
      }
    }
  }

  /// Clears all cached vehicle status entries, forcing fresh fetches.
  void clearCache() => _cache.clear();

  /// Clears the cached status for [vin] only, forcing a fresh fetch for
  /// that vehicle on the next call to [getVehicleStatus].
  void clearCacheFor(String vin) => _cache.clearFor(vin);
}
