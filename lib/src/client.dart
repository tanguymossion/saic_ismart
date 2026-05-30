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
import 'models/vehicle_control.dart';
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
  /// Underlying HTTP client — inject a `MockClient` in tests.
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
      return _parseResponse(response, currentEventId: eventId);
    } on SocketException catch (e) {
      throw SaicNetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw SaicNetworkException(message: e.message ?? 'Request timed out');
    }
  }

  /// Executes a POST request at [path] with AES-encrypted [jsonBody].
  ///
  /// [eventId] is sent as `event-id` header for the event-id polling pattern.
  Future<dynamic> post(
    String path,
    String jsonBody, {
    Map<String, String>? params,
    String eventId = '0',
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
    headers['event-id'] = eventId;

    try {
      final response = await rawClient.post(
        uri,
        headers: headers,
        body: encryptedBody,
      );
      return _parseResponse(response, currentEventId: eventId);
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
  /// - JSON code 2/3/7/8 → [SaicApiException] (fatal, no retry).
  /// - code 0 with no `data` key + `event-id` response header →
  ///   [_SaicEventIdRetryException] (caller retries with the new event-id).
  /// - **code != 0 while mid-event-id polling** ([currentEventId] != `'0'`) →
  ///   [_SaicEventIdRetryException] with the **same** event-id (retry trigger 2
  ///   per TECHNICAL_REFERENCE.md §4 — the server returns a non-zero code while
  ///   still processing the command; the Python client retries in this case).
  /// - Any other non-zero code on a fresh request → [SaicApiException].
  /// - Returns the `data` field of a successful (code == 0) response.
  ///
  /// Source: `base.py:__deserialize()`, `net/httpx/__init__.py:decrypt_httpx_response()`
  dynamic _parseResponse(http.Response response,
      {String currentEventId = '0'}) {
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
      final originalCt = response.headers['original-content-type'] ?? _kJson;
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
    // 3 = another remote command in progress (e.g. climate active)
    // 8 = command rejected by vehicle (e.g. feature not available on this model)
    if (code == 2 || code == 3 || code == 7 || code == 8) {
      throw SaicApiException(
        code: code as int,
        message: json['message'] as String? ?? 'Fatal API error',
      );
    }
    // Retry trigger 2 (TECHNICAL_REFERENCE.md §4): non-zero code while
    // mid-event-id polling means the server is still processing — retry
    // with the same event-id, not a new one.
    if (code != 0 && currentEventId != '0') {
      throw _SaicEventIdRetryException(currentEventId);
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
/// Inject [httpClient] to use a `MockClient` (from `package:http/testing.dart`) in tests.
/// Inject [cache] to override the default 600 s cooldown TTL.
class SaicClient {
  final SaicConfig _config;
  final _SaicHttpClient _http;
  final SaicCache _cache;
  final Duration _statusRetryDelay;
  final Duration _controlRetryDelay;
  final Duration _statusRetryTimeout;
  LoginResponse? _session;

  // ignore: public_member_api_docs
  SaicClient(
    SaicConfig config, {
    http.Client? httpClient,
    SaicCache? cache,
    Duration statusRetryDelay = const Duration(seconds: 3),
    Duration controlRetryDelay = const Duration(seconds: 1),
    Duration statusRetryTimeout = const Duration(seconds: 30),
  })  : _config = config,
        _http = _SaicHttpClient(
          httpClient ?? http.Client(),
          config.region,
        ),
        _cache = cache ?? SaicCache(),
        _statusRetryDelay = statusRetryDelay,
        _controlRetryDelay = controlRetryDelay,
        _statusRetryTimeout = statusRetryTimeout;

  /// The [LoginResponse] from the most recent successful [login] call, or
  /// `null` if [login] has not been called yet.
  LoginResponse? get session => _session;

  /// Returns `true` if the client has an active, non-expired session.
  bool get isLoggedIn {
    final s = _session;
    return s != null && !SaicAuth.isTokenExpired(s.tokenExpiration);
  }

  /// The expiration time of the current access token, or `null` if not logged
  /// in.
  DateTime? get tokenExpiration => _session?.tokenExpiration;

  /// Clears the current session. The next API call will require a new
  /// [login].
  void logout() {
    _session = null;
    _http.userToken = '';
    _cache.clear();
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

  /// Locks all doors on [vin].
  ///
  /// POSTs `rvcReqType: "1"` with `rvcParams: null`.
  /// Uses the event-id polling pattern (same as [getVehicleStatus]).
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/locks/__init__.py:lock_vehicle()`
  Future<VehicleControlResponse> lockVehicle(String vin) =>
      _vehicleControl(vin, RvcReqType.closeLocks, null);

  /// Unlocks all doors on [vin].
  ///
  /// POSTs `rvcReqType: "2"` with the five unlock params from section 7.
  /// Uses the event-id polling pattern (same as [getVehicleStatus]).
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/locks/__init__.py:unlock_vehicle()`
  Future<VehicleControlResponse> unlockVehicle(String vin) =>
      _vehicleControl(vin, RvcReqType.openLocks, [
        RvcParam(paramId: 4, paramValue: 'AA=='),
        RvcParam(paramId: 5, paramValue: 'AA=='),
        RvcParam(paramId: 6, paramValue: 'AA=='),
        RvcParam(paramId: 7, paramValue: _b64Byte(VehicleLockId.doors.raw)),
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='), // terminator
      ]);

  /// Opens the tailgate/boot on [vin].
  ///
  /// Same `rvcReqType: "2"` as [unlockVehicle] but with `paramId 7` set to
  /// `VehicleLockId.tailgate` (value `\x02`) instead of `\x03` for doors.
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/locks/__init__.py:open_tailgate()`
  Future<VehicleControlResponse> openTailgate(String vin) =>
      _vehicleControl(vin, RvcReqType.openLocks, [
        RvcParam(paramId: 4, paramValue: 'AA=='),
        RvcParam(paramId: 5, paramValue: 'AA=='),
        RvcParam(paramId: 6, paramValue: 'AA=='),
        RvcParam(paramId: 7, paramValue: _b64Byte(VehicleLockId.tailgate.raw)),
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='), // terminator
      ]);

  /// Triggers the "Find My Car" function on [vin] (horn + lights).
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/__init__.py:control_find_my_car()`
  Future<VehicleControlResponse> findMyCar(String vin) =>
      _vehicleControl(vin, RvcReqType.findMyCar, [
        RvcParam(paramId: 1, paramValue: 'AQ=='), // FIND_MY_CAR_ENABLE
        RvcParam(paramId: 2, paramValue: 'AQ=='), // FIND_MY_CAR_HORN
        RvcParam(paramId: 3, paramValue: 'AQ=='), // FIND_MY_CAR_LIGHTS
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='), // terminator
      ]);

  /// Stops the "Find My Car" function on [vin] (silences horn + lights).
  ///
  /// Sends the same `rvcReqType: "0"` as [findMyCar] but with all three
  /// activation params set to `\x00` (off).
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/__init__.py:control_find_my_car(should_stop=True)`
  Future<VehicleControlResponse> stopFindMyCar(String vin) =>
      _vehicleControl(vin, RvcReqType.findMyCar, [
        RvcParam(paramId: 1, paramValue: 'AA=='), // FIND_MY_CAR_ENABLE off
        RvcParam(paramId: 2, paramValue: 'AA=='), // FIND_MY_CAR_HORN off
        RvcParam(paramId: 3, paramValue: 'AA=='), // FIND_MY_CAR_LIGHTS off
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='), // terminator
      ]);

  /// Starts remote climate control on [vin].
  ///
  /// [temperatureIndex] is 0–15. Meaning of each index is undocumented —
  /// index 8 is the observed default in the Python client.
  ///
  /// **Note:** while climate is active, all other vehicle control commands will
  /// fail with [SaicApiException] (code: 3). Call [stopClimate] first.
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/climate/__init__.py:start_ac()`
  Future<VehicleControlResponse> startClimate(
    String vin, {
    int temperatureIndex = 8,
    ClimateMode mode = ClimateMode.normal,
  }) =>
      _vehicleControl(vin, RvcReqType.climate, [
        RvcParam(paramId: 19, paramValue: _b64Byte(mode.raw)),
        RvcParam(paramId: 20, paramValue: _b64Byte(temperatureIndex)),
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='),
      ]);

  /// Stops remote climate control on [vin].
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/climate/__init__.py:stop_ac()`
  Future<VehicleControlResponse> stopClimate(String vin) =>
      _vehicleControl(vin, RvcReqType.climate, [
        RvcParam(paramId: 19, paramValue: _b64Byte(ClimateMode.off.raw)),
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='),
      ]);

  /// Starts ventilation without A/C.
  ///
  /// Equivalent to `startClimate(vin, mode: ClimateMode.blow)`.
  ///
  /// **Note:** while climate is active, all other vehicle control commands will
  /// fail with [SaicApiException] (code: 3). Call [stopClimate] first.
  Future<VehicleControlResponse> startBlowing(String vin) =>
      startClimate(vin, mode: ClimateMode.blow);

  /// Starts defrost mode.
  ///
  /// Equivalent to `startClimate(vin, mode: ClimateMode.defrost)`. Useful in
  /// winter to clear windscreen before driving.
  ///
  /// **Note:** while climate is active, all other vehicle control commands will
  /// fail with [SaicApiException] (code: 3). Call [stopClimate] first.
  Future<VehicleControlResponse> startDefrost(String vin) =>
      startClimate(vin, mode: ClimateMode.defrost);

  /// Controls the heated seats on [vin].
  ///
  /// Pass [driverLevel] and/or [passengerLevel] to set each seat independently.
  /// Both default to [HeatLevel.off].
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/climate/__init__.py:control_heated_seats()`
  Future<VehicleControlResponse> controlHeatedSeats(
    String vin, {
    HeatLevel driverLevel = HeatLevel.off,
    HeatLevel passengerLevel = HeatLevel.off,
  }) =>
      _vehicleControl(vin, RvcReqType.heatedSeats, [
        RvcParam(paramId: 17, paramValue: _b64Byte(driverLevel.raw)),
        RvcParam(paramId: 18, paramValue: _b64Byte(passengerLevel.raw)),
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='),
      ]);

  /// Controls the rear window heating element.
  ///
  /// Useful in winter to clear condensation or ice. [enable] defaults to
  /// `true`; pass `false` to turn the heater off.
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/climate/__init__.py:control_rear_window_heat()`
  Future<VehicleControlResponse> controlRearWindowHeat(
    String vin, {
    bool enable = true,
  }) =>
      _vehicleControl(vin, RvcReqType.remoteHeatRearWindow, [
        RvcParam(paramId: 23, paramValue: enable ? 'AQ==' : 'AA=='),
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='),
      ]);

  /// Opens or closes the sunroof remotely.
  ///
  /// Not all SAIC vehicles have a sunroof — check `vehicleModelConfiguration`
  /// from [getVehicles] for item code `S35` with `itemValue == '1'` before
  /// calling. If the vehicle doesn't support it, the server will return an
  /// error.
  ///
  /// Endpoint: `POST /vehicle/control`
  /// Source: `api/vehicle/windows/__init__.py:control_sunroof()`
  Future<VehicleControlResponse> controlSunroof(
    String vin, {
    bool open = true,
  }) =>
      _vehicleControl(vin, RvcReqType.windows, [
        RvcParam(paramId: 8, paramValue: 'AQ=='),
        RvcParam(paramId: 13, paramValue: open ? 'Aw==' : 'AA=='),
        RvcParam(paramId: 255, paramValue: 'AAAAAA=='),
      ]);

  /// Base64-encodes a single byte [v] (0–255).
  static String _b64Byte(int v) => base64Encode([v]);

  Future<VehicleControlResponse> _vehicleControl(
    String vin,
    RvcReqType reqType,
    List<RvcParam>? params,
  ) async {
    final body = jsonEncode({
      'vin': sha256Hex(vin),
      'rvcReqType': reqType.value,
      'rvcParams': params?.map((p) => p.toJson()).toList(),
    });

    var eventId = '0';
    var retryCount = 0;
    final deadline = DateTime.now().add(_statusRetryTimeout);

    while (true) {
      try {
        final rawData = await _http.post(
          '/vehicle/control',
          body,
          eventId: eventId,
        );
        return VehicleControlResponse.fromJson(rawData as Map<String, dynamic>);
      } on _SaicEventIdRetryException catch (e) {
        if (DateTime.now().isAfter(deadline)) {
          throw SaicTimeoutException(
            message: 'vehicleControl timed out after 30 s '
                '(event-id: ${e.eventId})',
          );
        }
        eventId = e.eventId;
        // wait_chain(wait_fixed(1s) + wait_none()): 1 s before the first
        // retry, then immediate for subsequent retries (mirrors the Python
        // client's per-command wait_chain — TECHNICAL_REFERENCE.md §4).
        if (retryCount == 0) await Future.delayed(_controlRetryDelay);
        retryCount++;
      }
    }
  }
}
