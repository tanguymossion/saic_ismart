import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saic_ismart/src/auth.dart';
import 'package:saic_ismart/src/client.dart';
import 'package:saic_ismart/src/exceptions.dart';
import 'package:saic_ismart/src/models/vehicle_control.dart';
import 'package:saic_ismart/src/utils/crypto_utils.dart';
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _vin = 'LSJA24B19NB123456';
const _config = SaicConfig(username: 'test@example.com', password: 'pw');

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

http.Response _encryptedResponse(
  String plainJson, {
  String appSendDate = '1700000000000',
  Map<String, String> extraHeaders = const {},
}) {
  const ct = 'application/json';
  final body = encryptBody(
    plainJson,
    deriveResponseKey(appSendDate, ct),
    deriveResponseIv(appSendDate),
  );
  return http.Response(body, 200, headers: {
    'app-send-date': appSendDate,
    'original-content-type': ct,
    ...extraHeaders,
  });
}

http.Response _pendingResponse(String eventId) => _encryptedResponse(
      '{"code":0}',
      extraHeaders: {'event-id': eventId},
    );

http.Response _controlResponse({
  int? failureType,
  dynamic rvcReqSts,
}) =>
    _encryptedResponse(jsonEncode({
      'code': 0,
      'data': {
        if (failureType != null) 'failureType': failureType,
        if (rvcReqSts != null) 'rvcReqSts': rvcReqSts,
      },
    }));

/// Builds a [SaicClient] whose mock handler responds to login then delegates
/// all other requests to [onApi].
Future<(SaicClient, List<http.Request>)> _makeClient({
  required Future<http.Response> Function(http.Request) onApi,
  Duration statusRetryDelay = Duration.zero,
}) async {
  final requests = <http.Request>[];
  final mock = MockClient((req) async {
    if (req.url.path.endsWith('/oauth/token')) {
      return _encryptedResponse(_loginBody());
    }
    requests.add(req);
    return onApi(req);
  });
  final client = SaicClient(
    _config,
    httpClient: mock,
    statusRetryDelay: statusRetryDelay,
  );
  await client.login();
  return (client, requests);
}

// ── Helpers to decode the captured request body ───────────────────────────────

/// Decrypts and parses the JSON body of a captured POST request.
Map<String, dynamic> _decryptRequestBody(http.Request req) {
  final ts = req.headers['APP-SEND-DATE']!;
  final keyHex = deriveRequestKey(
    '/vehicle/control',
    '459771',
    'tok',
    ts,
    'application/json',
  );
  final plain = decryptBody(req.body, keyHex, deriveRequestIv(ts));
  return jsonDecode(plain) as Map<String, dynamic>;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── lockVehicle request ───────────────────────────────────────────────────────

  group('lockVehicle — request', () {
    late Map<String, dynamic> body;

    setUp(() async {
      final (client, requests) = await _makeClient(
        onApi: (_) async => _controlResponse(),
      );
      await client.lockVehicle(_vin);
      body = _decryptRequestBody(requests.first);
    });

    test('sends rvcReqType "1"', () {
      expect(body['rvcReqType'], '1');
    });

    test('sends rvcParams null', () {
      expect(body['rvcParams'], isNull);
    });

    test('hashes VIN with SHA-256', () {
      expect(body['vin'], sha256Hex(_vin));
      expect(body['vin'], isNot(_vin));
    });

    test('POSTs to /vehicle/control', () async {
      http.Request? captured;
      final (client, _) = await _makeClient(onApi: (req) async {
        captured = req;
        return _controlResponse();
      });
      await client.lockVehicle(_vin);
      expect(
        captured?.url.toString(),
        'https://gateway-mg-eu.soimt.com/api.app/v1/vehicle/control',
      );
    });
  });

  // ── unlockVehicle request ─────────────────────────────────────────────────────

  group('unlockVehicle — request', () {
    late Map<String, dynamic> body;

    setUp(() async {
      final (client, requests) = await _makeClient(
        onApi: (_) async => _controlResponse(),
      );
      await client.unlockVehicle(_vin);
      body = _decryptRequestBody(requests.first);
    });

    test('sends rvcReqType "2"', () {
      expect(body['rvcReqType'], '2');
    });

    test('hashes VIN with SHA-256', () {
      expect(body['vin'], sha256Hex(_vin));
    });

    test('sends exactly 5 params', () {
      expect((body['rvcParams'] as List).length, 5);
    });

    test('params are in correct order', () {
      final params = body['rvcParams'] as List;
      expect(params[0]['paramId'], 4);
      expect(params[1]['paramId'], 5);
      expect(params[2]['paramId'], 6);
      expect(params[3]['paramId'], 7);
      expect(params[4]['paramId'], 255);
    });

    test('paramId 4,5,6 have value "AA=="', () {
      final params = body['rvcParams'] as List;
      expect(params[0]['paramValue'], 'AA==');
      expect(params[1]['paramValue'], 'AA==');
      expect(params[2]['paramValue'], 'AA==');
    });

    test('paramId 7 has value "Aw==" (DOORS=3)', () {
      final params = body['rvcParams'] as List;
      expect(params[3]['paramValue'], 'Aw==');
    });

    test('paramId 255 (terminator) has value "AAAAAA=="', () {
      final params = body['rvcParams'] as List;
      expect(params[4]['paramValue'], 'AAAAAA==');
    });
  });

  // ── event-id polling ──────────────────────────────────────────────────────────

  group('lockVehicle — event-id polling', () {
    test('retries after pending response and returns data on second call',
        () async {
      var callCount = 0;
      final (client, _) = await _makeClient(
        statusRetryDelay: Duration.zero,
        onApi: (_) async {
          callCount++;
          if (callCount == 1) return _pendingResponse('evt-42');
          return _controlResponse(failureType: 0);
        },
      );
      final result = await client.lockVehicle(_vin);
      expect(callCount, 2);
      expect(result.failureType, 0);
    });

    test('sends event-id header on retry', () async {
      final capturedEventIds = <String>[];
      var callCount = 0;
      final (client, _) = await _makeClient(
        statusRetryDelay: Duration.zero,
        onApi: (req) async {
          capturedEventIds.add(req.headers['event-id'] ?? '');
          callCount++;
          if (callCount == 1) return _pendingResponse('evt-99');
          return _controlResponse();
        },
      );
      await client.lockVehicle(_vin);
      expect(capturedEventIds[0], '0');
      expect(capturedEventIds[1], 'evt-99');
    });

    test('throws SaicTimeoutException when polling exhausted', () async {
      final clientWithShortTimeout = SaicClient(
        _config,
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/oauth/token')) {
            return _encryptedResponse(_loginBody());
          }
          return _pendingResponse('evt-x');
        }),
        statusRetryDelay: Duration.zero,
        statusRetryTimeout: Duration.zero,
      );
      await clientWithShortTimeout.login();
      expect(
        clientWithShortTimeout.lockVehicle(_vin),
        throwsA(isA<SaicTimeoutException>()),
      );
    });
  });

  // ── VehicleControlResponse.fromJson ──────────────────────────────────────────

  group('VehicleControlResponse.fromJson', () {
    test('parses failureType', () {
      final r = VehicleControlResponse.fromJson({'failureType': 3});
      expect(r.failureType, 3);
    });

    test('rvcReqSts absent → null', () {
      final r = VehicleControlResponse.fromJson({});
      expect(r.rvcReqSts, isNull);
    });

    test('rvcReqSts as Base64 string decodes correctly', () {
      // "Aw==" = base64([0x03])
      final r = VehicleControlResponse.fromJson({'rvcReqSts': 'Aw=='});
      expect(r.rvcReqSts, Uint8List.fromList([0x03]));
    });

    test('rvcReqSts as int 3 → [0x03]', () {
      final r = VehicleControlResponse.fromJson({'rvcReqSts': 3});
      expect(r.rvcReqSts, Uint8List.fromList([0x03]));
    });

    test('rvcReqSts as int 0 → empty bytes', () {
      final r = VehicleControlResponse.fromJson({'rvcReqSts': 0});
      expect(r.rvcReqSts, isEmpty);
    });

    test('rvcReqSts as multi-byte Base64 decodes correctly', () {
      // "AAAAAA==" = base64([0x00, 0x00, 0x00, 0x00])
      final r =
          VehicleControlResponse.fromJson({'rvcReqSts': 'AAAAAA=='});
      expect(r.rvcReqSts, Uint8List.fromList([0x00, 0x00, 0x00, 0x00]));
    });

    test('basicVehicleStatus absent → null', () {
      final r = VehicleControlResponse.fromJson({});
      expect(r.basicVehicleStatus, isNull);
    });

    test('gpsPosition absent → null', () {
      final r = VehicleControlResponse.fromJson({});
      expect(r.gpsPosition, isNull);
    });
  });

  // ── error handling ────────────────────────────────────────────────────────────

  group('lockVehicle — error handling', () {
    test('throws SaicApiException on non-zero API code', () async {
      final (client, _) = await _makeClient(
        onApi: (_) async =>
            _encryptedResponse('{"code":7,"message":"Fatal"}'),
      );
      expect(client.lockVehicle(_vin), throwsA(isA<SaicApiException>()));
    });

    test('throws SaicAuthException on HTTP 401', () async {
      final (client, _) = await _makeClient(
        onApi: (_) async => http.Response('Unauthorized', 401),
      );
      expect(client.lockVehicle(_vin), throwsA(isA<SaicAuthException>()));
    });
  });

  // ── RvcReqType enum ───────────────────────────────────────────────────────────

  group('RvcReqType', () {
    test('closeLocks value is "1"',
        () => expect(RvcReqType.closeLocks.value, '1'));
    test('openLocks value is "2"',
        () => expect(RvcReqType.openLocks.value, '2'));
    test('climate value is "6"',
        () => expect(RvcReqType.climate.value, '6'));
    test('findMyCar value is "0"',
        () => expect(RvcReqType.findMyCar.value, '0'));
  });

  // ── findMyCar request ─────────────────────────────────────────────────────────

  group('findMyCar — request', () {
    late Map<String, dynamic> body;

    setUp(() async {
      final (client, requests) = await _makeClient(
        onApi: (_) async => _controlResponse(),
      );
      await client.findMyCar(_vin);
      body = _decryptRequestBody(requests.first);
    });

    test('sends rvcReqType "0"', () {
      expect(body['rvcReqType'], '0');
    });

    test('hashes VIN with SHA-256', () {
      expect(body['vin'], sha256Hex(_vin));
      expect(body['vin'], isNot(_vin));
    });

    test('sends exactly 4 params', () {
      expect((body['rvcParams'] as List).length, 4);
    });

    test('params are in correct order', () {
      final params = body['rvcParams'] as List;
      expect(params[0]['paramId'], 1); // FIND_MY_CAR_ENABLE
      expect(params[1]['paramId'], 2); // FIND_MY_CAR_HORN
      expect(params[2]['paramId'], 3); // FIND_MY_CAR_LIGHTS
      expect(params[3]['paramId'], 255); // terminator
    });

    test('paramId 1,2,3 have value "AQ=="', () {
      final params = body['rvcParams'] as List;
      expect(params[0]['paramValue'], 'AQ==');
      expect(params[1]['paramValue'], 'AQ==');
      expect(params[2]['paramValue'], 'AQ==');
    });

    test('terminator paramId 255 has value "AAAAAA=="', () {
      final params = body['rvcParams'] as List;
      expect(params[3]['paramValue'], 'AAAAAA==');
    });
  });

  // ── RvcParamsId enum ──────────────────────────────────────────────────────────

  group('RvcParamsId', () {
    test('lockId value is 7', () => expect(RvcParamsId.lockId.value, 7));
    test('paramsMax value is 255',
        () => expect(RvcParamsId.paramsMax.value, 255));
    test('unk4 value is 4', () => expect(RvcParamsId.unk4.value, 4));
  });
}
