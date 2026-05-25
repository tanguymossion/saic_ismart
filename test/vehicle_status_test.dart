import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saic_ismart/src/auth.dart';
import 'package:saic_ismart/src/client.dart';
import 'package:saic_ismart/src/exceptions.dart';
import 'package:saic_ismart/src/models/vehicle_status.dart';
import 'package:saic_ismart/src/utils/crypto_utils.dart';
import 'package:test/test.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

const _vin = 'LSJA24B19NB123456';

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

/// Returns an encrypted response with no `data` field and the given [eventId]
/// header, simulating the server's first async-processing reply.
http.Response _pendingResponse(String eventId) => _encryptedResponse(
      '{"code":0}',
      extraHeaders: {'event-id': eventId},
    );

http.Response _statusResponse(Map<String, dynamic> data) =>
    _encryptedResponse(jsonEncode({'code': 0, 'data': data}));

/// Builds a [SaicClient] backed by a [MockClient] that responds to login and
/// delegates all other requests to [onApi].
///
/// [statusRetryDelay] is forwarded to [SaicClient] so tests can pass
/// [Duration.zero] and avoid real sleeps between event-id retries.
Future<SaicClient> _client(
  Future<http.Response> Function(http.Request) onApi, {
  Duration statusRetryDelay = Duration.zero,
}) async {
  final mock = MockClient((req) async {
    if (req.url.path.endsWith('/oauth/token')) {
      return _encryptedResponse(_loginBody());
    }
    return onApi(req);
  });
  final client = SaicClient(
    const SaicConfig(username: 'test@example.com', password: 'pw'),
    httpClient: mock,
    statusRetryDelay: statusRetryDelay,
  );
  await client.login();
  return client;
}

// ── Full response fixture ─────────────────────────────────────────────────────

const _fullBasic = {
  'batteryVoltage': 12,
  'bonnetStatus': 0,
  'bootStatus': 0,
  'canBusActive': 1,
  'clstrDspdFuelLvlSgmt': 8,
  'currentJourneyId': 42,
  'currentJourneyDistance': 5000,
  'dippedBeamStatus': 0,
  'driverDoor': 0,
  'driverWindow': 0,
  'engineStatus': 1,
  'extendedData1': 0,
  'extendedData2': 0,
  'exteriorTemperature': 25,
  'frontLeftSeatHeatLevel': 0,
  'frontLeftTyrePressure': 240,
  'frontRightSeatHeatLevel': 0,
  'frontRightTyrePressure': 240,
  'fuelLevelPrc': 75,
  'fuelRange': 450000,
  'fuelRangeElec': 300000,
  'handBrake': 0,
  'interiorTemperature': 22,
  'lastKeySeen': 1,
  'lockStatus': 1,
  'mainBeamStatus': 0,
  'mileage': 12345,
  'passengerDoor': 0,
  'passengerWindow': 0,
  'powerMode': 1,
  'rearLeftDoor': 0,
  'rearLeftTyrePressure': 235,
  'rearLeftWindow': 0,
  'rearRightDoor': 0,
  'rearRightTyrePressure': 235,
  'rearRightWindow': 0,
  'remoteClimateStatus': 0,
  'rmtHtdRrWndSt': 0,
  'sideLightStatus': 0,
  'steeringHeatLevel': 0,
  'steeringWheelHeatFailureReason': 0,
  'sunroofStatus': 0,
  'timeOfLastCANBUSActivity': 1700000000,
  'vehElecRngDsp': 300,
  'vehicleAlarmStatus': 0,
  'wheelTyreMonitorStatus': 0,
};

const _fullGps = {
  'gpsStatus': 3,
  'timeStamp': 1700000000,
  'wayPoint': {
    'position': {'latitude': 51507222, 'longitude': 127000, 'altitude': 35},
    'hdop': 1,
    'heading': 180,
    'satellites': 8,
    'speed': 0,
  },
};

const _fullStatusData = {
  'basicVehicleStatus': _fullBasic,
  'gpsPosition': _fullGps,
  'extendedVehicleStatus': {
    'alertDataSum': [
      {'id': 3, 'value': 1},
      {'id': 7, 'value': 255},
    ],
  },
  'statusTime': 1700000000,
};

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Full parsing ────────────────────────────────────────────────────────────

  group('getVehicleStatus — full parsing', () {
    late VehicleStatus status;

    setUpAll(() async {
      final c = await _client((_) async => _statusResponse(_fullStatusData));
      status = await c.getVehicleStatus(_vin);
    });

    test('parses statusTime', () => expect(status.statusTime, 1700000000));

    group('BasicVehicleStatus', () {
      late BasicVehicleStatus b;
      setUp(() => b = status.basicVehicleStatus!);

      test('batteryVoltage', () => expect(b.batteryVoltage, 12));
      test('engineStatus', () => expect(b.engineStatus, 1));
      test('fuelLevelPrc', () => expect(b.fuelLevelPrc, 75));
      test('fuelRange', () => expect(b.fuelRange, 450000));
      test('fuelRangeElec', () => expect(b.fuelRangeElec, 300000));
      test('mileage', () => expect(b.mileage, 12345));
      test('lockStatus', () => expect(b.lockStatus, 1));
      test('handBrake', () => expect(b.handBrake, 0));
      test('exteriorTemperature', () => expect(b.exteriorTemperature, 25));
      test('interiorTemperature', () => expect(b.interiorTemperature, 22));
      test('frontLeftTyrePressure',
          () => expect(b.frontLeftTyrePressure, 240));
      test('timeOfLastCANBUSActivity',
          () => expect(b.timeOfLastCANBUSActivity, 1700000000));
      test('vehElecRngDsp', () => expect(b.vehElecRngDsp, 300));
    });

    group('GpsPosition', () {
      late GpsPosition g;
      setUp(() => g = status.gpsPosition!);

      test('gpsStatus', () => expect(g.gpsStatus, GpsStatus.fix3d));
      test('timeStamp', () => expect(g.timeStamp, 1700000000));
      test('raw latitude', () => expect(g.wayPoint!.position!.latitude, 51507222));
      test('raw longitude', () => expect(g.wayPoint!.position!.longitude, 127000));
      test('altitude', () => expect(g.wayPoint!.position!.altitude, 35));
      test('hdop', () => expect(g.wayPoint!.hdop, 1));
      test('heading', () => expect(g.wayPoint!.heading, 180));
      test('satellites', () => expect(g.wayPoint!.satellites, 8));
      test('speed', () => expect(g.wayPoint!.speed, 0));
    });

    group('extendedVehicleStatus', () {
      test('alertDataSum has two entries', () {
        expect(status.extendedVehicleStatus!.alertDataSum, hasLength(2));
      });

      test('first alert id and value', () {
        final a = status.extendedVehicleStatus!.alertDataSum[0];
        expect(a.id, 3);
        expect(a.value, 1);
      });

      test('second alert id and value', () {
        final a = status.extendedVehicleStatus!.alertDataSum[1];
        expect(a.id, 7);
        expect(a.value, 255);
      });
    });
  });

  // ── Partial / nullable parsing ──────────────────────────────────────────────

  group('getVehicleStatus — partial response does not throw', () {
    test('all top-level fields null', () async {
      final c = await _client(
        (_) async => _statusResponse({}),
      );
      final s = await c.getVehicleStatus(_vin);
      expect(s.basicVehicleStatus, isNull);
      expect(s.gpsPosition, isNull);
      expect(s.extendedVehicleStatus, isNull);
      expect(s.statusTime, isNull);
    });

    test('basicVehicleStatus present but all fields null', () async {
      final c = await _client(
        (_) async => _statusResponse({'basicVehicleStatus': {}}),
      );
      final s = await c.getVehicleStatus(_vin);
      final b = s.basicVehicleStatus!;
      expect(b.engineStatus, isNull);
      expect(b.fuelLevelPrc, isNull);
      expect(b.fuelRangeElec, isNull);
    });

    test('gpsPosition present but wayPoint null', () async {
      final c = await _client(
        (_) async => _statusResponse({
          'gpsPosition': {'gpsStatus': 0, 'timeStamp': null, 'wayPoint': null},
        }),
      );
      final g = (await c.getVehicleStatus(_vin)).gpsPosition!;
      expect(g.latitudeDegrees, isNull);
      expect(g.longitudeDegrees, isNull);
    });
  });

  // ── Computed properties ─────────────────────────────────────────────────────

  group('BasicVehicleStatus.isEngineRunning', () {
    test('true when engineStatus == 1', () {
      const b = BasicVehicleStatus(engineStatus: 1);
      expect(b.isEngineRunning, isTrue);
    });

    test('false when engineStatus != 1', () {
      expect(const BasicVehicleStatus(engineStatus: 0).isEngineRunning, isFalse);
      expect(const BasicVehicleStatus().isEngineRunning, isFalse);
    });
  });

  group('BasicVehicleStatus.isParked', () {
    test('true when engine off (engineStatus != 1)', () {
      expect(const BasicVehicleStatus(engineStatus: 0, handBrake: 0).isParked,
          isTrue);
    });

    test('true when engine running but handbrake on', () {
      expect(const BasicVehicleStatus(engineStatus: 1, handBrake: 1).isParked,
          isTrue);
    });

    test('false when engine running and handbrake off', () {
      expect(const BasicVehicleStatus(engineStatus: 1, handBrake: 0).isParked,
          isFalse);
    });

    test('true when both fields are null', () {
      // null engineStatus → not 1 → parked
      expect(const BasicVehicleStatus().isParked, isTrue);
    });
  });

  // ── GPS degree conversion ────────────────────────────────────────────────────

  group('GpsPosition degree getters', () {
    const gps = GpsPosition(
      wayPoint: WayPoint(
        position: Position(latitude: 51507222, longitude: 127000),
      ),
    );

    test('latitudeDegrees divides by 1,000,000', () {
      expect(gps.latitudeDegrees, closeTo(51.507222, 1e-9));
    });

    test('longitudeDegrees divides by 1,000,000', () {
      expect(gps.longitudeDegrees, closeTo(0.127, 1e-9));
    });

    test('negative longitude works correctly', () {
      const neg = GpsPosition(
        wayPoint: WayPoint(
          position: Position(latitude: 51507222, longitude: -127000),
        ),
      );
      expect(neg.longitudeDegrees, closeTo(-0.127, 1e-9));
    });

    test('returns null when wayPoint is null', () {
      expect(const GpsPosition().latitudeDegrees, isNull);
      expect(const GpsPosition().longitudeDegrees, isNull);
    });

    test('returns null when position is null', () {
      expect(
        const GpsPosition(wayPoint: WayPoint()).latitudeDegrees,
        isNull,
      );
    });
  });

  // ── GpsStatus enum ──────────────────────────────────────────────────────────

  group('GpsStatus.fromValue', () {
    test('maps 0 to noSignal', () => expect(GpsStatus.fromValue(0), GpsStatus.noSignal));
    test('maps 1 to timeFix', () => expect(GpsStatus.fromValue(1), GpsStatus.timeFix));
    test('maps 2 to fix2d', () => expect(GpsStatus.fromValue(2), GpsStatus.fix2d));
    test('maps 3 to fix3d', () => expect(GpsStatus.fromValue(3), GpsStatus.fix3d));
    test('unknown value falls back to noSignal',
        () => expect(GpsStatus.fromValue(99), GpsStatus.noSignal));
  });

  // ── operator == / hashCode ──────────────────────────────────────────────────

  group('operator == and hashCode', () {
    test('VehicleStatus equality', () {
      const a = VehicleStatus(statusTime: 1);
      const b = VehicleStatus(statusTime: 1);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('VehicleStatus inequality on statusTime', () {
      expect(
        const VehicleStatus(statusTime: 1),
        isNot(equals(const VehicleStatus(statusTime: 2))),
      );
    });

    test('BasicVehicleStatus equality', () {
      const a = BasicVehicleStatus(engineStatus: 1, mileage: 1000);
      const b = BasicVehicleStatus(engineStatus: 1, mileage: 1000);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('BasicVehicleStatus inequality', () {
      expect(
        const BasicVehicleStatus(mileage: 1000),
        isNot(equals(const BasicVehicleStatus(mileage: 999))),
      );
    });

    test('GpsPosition equality', () {
      const a = GpsPosition(gpsStatus: GpsStatus.fix3d, timeStamp: 1000);
      const b = GpsPosition(gpsStatus: GpsStatus.fix3d, timeStamp: 1000);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('Position equality', () {
      const a = Position(latitude: 51507222, longitude: 127000, altitude: 35);
      const b = Position(latitude: 51507222, longitude: 127000, altitude: 35);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('ExtendedVehicleStatus equality with empty lists', () {
      const a = ExtendedVehicleStatus(alertDataSum: []);
      const b = ExtendedVehicleStatus(alertDataSum: []);
      expect(a, equals(b));
    });

    test('ExtendedVehicleStatus equality with matching alerts', () {
      final a = ExtendedVehicleStatus(alertDataSum: [
        const VehicleAlertInfo(id: 3, value: 1),
        const VehicleAlertInfo(id: 7, value: 255),
      ]);
      final b = ExtendedVehicleStatus(alertDataSum: [
        const VehicleAlertInfo(id: 3, value: 1),
        const VehicleAlertInfo(id: 7, value: 255),
      ]);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('ExtendedVehicleStatus inequality when alerts differ', () {
      final a = ExtendedVehicleStatus(
          alertDataSum: [const VehicleAlertInfo(id: 3, value: 1)]);
      final b = ExtendedVehicleStatus(
          alertDataSum: [const VehicleAlertInfo(id: 3, value: 2)]);
      expect(a, isNot(equals(b)));
    });

    test('VehicleAlertInfo equality and hashCode', () {
      const a = VehicleAlertInfo(id: 42, value: 7);
      const b = VehicleAlertInfo(id: 42, value: 7);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('VehicleAlertInfo inequality', () {
      const a = VehicleAlertInfo(id: 1, value: 0);
      const b = VehicleAlertInfo(id: 1, value: 1);
      expect(a, isNot(equals(b)));
    });

    test('ExtendedVehicleStatus parses empty alertDataSum', () {
      final s = ExtendedVehicleStatus.fromJson({'alertDataSum': []});
      expect(s.alertDataSum, isEmpty);
    });

    test('ExtendedVehicleStatus parses absent alertDataSum as empty', () {
      final s = ExtendedVehicleStatus.fromJson({});
      expect(s.alertDataSum, isEmpty);
    });

    // Flat integer list observed on MG3 Hybrid EU.
    test('ExtendedVehicleStatus parses flat int list (MG3 Hybrid EU format)',
        () {
      final s = ExtendedVehicleStatus.fromJson({
        'alertDataSum': [0, 0, 0, 0],
      });
      expect(s.alertDataSum, hasLength(4));
      for (final a in s.alertDataSum) {
        expect(a.id, 0);
        expect(a.value, 0);
      }
    });

    test('ExtendedVehicleStatus flat int list preserves id values', () {
      final s = ExtendedVehicleStatus.fromJson({
        'alertDataSum': [5, 12, 255],
      });
      expect(s.alertDataSum[0], const VehicleAlertInfo(id: 5, value: 0));
      expect(s.alertDataSum[1], const VehicleAlertInfo(id: 12, value: 0));
      expect(s.alertDataSum[2], const VehicleAlertInfo(id: 255, value: 0));
    });

    test('ExtendedVehicleStatus object list still parses (ASN.1 form)', () {
      final s = ExtendedVehicleStatus.fromJson({
        'alertDataSum': [
          {'id': 3, 'value': 1},
          {'id': 7, 'value': 255},
        ],
      });
      expect(s.alertDataSum[0], const VehicleAlertInfo(id: 3, value: 1));
      expect(s.alertDataSum[1], const VehicleAlertInfo(id: 7, value: 255));
    });
  });

  // ── Request — VIN hashing and query params ──────────────────────────────────

  group('getVehicleStatus — request', () {
    late http.Request captured;

    setUp(() async {
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/oauth/token')) {
          return _encryptedResponse(_loginBody());
        }
        captured = req;
        return _statusResponse(_fullStatusData);
      });
      final client = SaicClient(
        const SaicConfig(username: 'test@example.com', password: 'pw'),
        httpClient: mock,
        statusRetryDelay: Duration.zero,
      );
      await client.login();
      await client.getVehicleStatus(_vin);
    });

    test('sends SHA-256 hashed VIN, not raw VIN', () {
      final params = Uri.splitQueryString(captured.url.query);
      expect(params['vin'], isNot(_vin));
      expect(params['vin'], sha256Hex(_vin));
    });

    test('always sends vehStatusReqType=2 (quirk #11)', () {
      final params = Uri.splitQueryString(captured.url.query);
      expect(params['vehStatusReqType'], '2');
    });

    test('calls correct EU endpoint path', () {
      expect(captured.url.path, contains('/vehicle/status'));
    });

    test('sends event-id: 0 on initial request', () {
      expect(captured.headers['event-id'], '0');
    });
  });

  // ── Event-id retry ───────────────────────────────────────────────────────────

  group('getVehicleStatus — event-id retry', () {
    test('retries after pending response and returns data on second call',
        () async {
      var callCount = 0;
      final c = await _client((_) async {
        callCount++;
        if (callCount == 1) return _pendingResponse('evt-001');
        return _statusResponse(_fullStatusData);
      });
      final status = await c.getVehicleStatus(_vin);
      expect(callCount, 2);
      expect(status.statusTime, 1700000000);
    });

    test('sends the event-id from the pending response on the retry request',
        () async {
      final sentEventIds = <String>[];
      final c = await _client((req) async {
        sentEventIds.add(req.headers['event-id'] ?? '');
        if (sentEventIds.length == 1) return _pendingResponse('evt-xyz');
        return _statusResponse(_fullStatusData);
      });
      await c.getVehicleStatus(_vin);
      expect(sentEventIds[0], '0');
      expect(sentEventIds[1], 'evt-xyz');
    });

    test('throws SaicTimeoutException when retry timeout is exhausted',
        () async {
      final c = SaicClient(
        const SaicConfig(username: 'test@example.com', password: 'pw'),
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/oauth/token')) {
            return _encryptedResponse(_loginBody());
          }
          return _pendingResponse('evt-loop');
        }),
        statusRetryDelay: Duration.zero,
        statusRetryTimeout: Duration.zero, // deadline is already past on first retry
      );
      await c.login();
      expect(c.getVehicleStatus(_vin), throwsA(isA<SaicTimeoutException>()));
    });

    test('retries when server returns non-zero code mid-polling (§4 trigger 2)',
        () async {
      var callCount = 0;
      final c = await _client((req) async {
        callCount++;
        if (callCount == 1) return _pendingResponse('evt-001');
        if (callCount == 2) {
          return _encryptedResponse('{"code":4,"message":"processing"}');
        }
        return _statusResponse(_fullStatusData);
      });
      final status = await c.getVehicleStatus(_vin);
      expect(callCount, 3);
      expect(status.statusTime, 1700000000);
    });

    test('retries with same event-id on non-zero mid-poll response', () async {
      final sentEventIds = <String>[];
      var callCount = 0;
      final c = await _client((req) async {
        sentEventIds.add(req.headers['event-id'] ?? '');
        callCount++;
        if (callCount == 1) return _pendingResponse('evt-abc');
        if (callCount == 2) {
          return _encryptedResponse('{"code":4,"message":"processing"}');
        }
        return _statusResponse(_fullStatusData);
      });
      await c.getVehicleStatus(_vin);
      expect(sentEventIds[0], '0');        // initial request
      expect(sentEventIds[1], 'evt-abc');  // first retry (from pending)
      expect(sentEventIds[2], 'evt-abc');  // second retry (same id, non-zero)
    });

    test('does NOT retry non-zero code on fresh request (event-id == 0)',
        () async {
      final c = await _client(
        (_) async => _encryptedResponse('{"code":4,"message":"processing"}'),
      );
      expect(c.getVehicleStatus(_vin), throwsA(isA<SaicApiException>()));
    });
  });

  // ── Error handling ──────────────────────────────────────────────────────────

  group('getVehicleStatus — error handling', () {
    test('throws SaicAuthException on HTTP 401', () async {
      final c = await _client(
        (_) async => http.Response('Unauthorized', 401),
      );
      expect(c.getVehicleStatus(_vin), throwsA(isA<SaicAuthException>()));
    });

    test('throws SaicApiException on fatal code 7', () async {
      final c = await _client(
        (_) async => _encryptedResponse('{"code":7,"message":"Fatal"}'),
      );
      expect(c.getVehicleStatus(_vin), throwsA(isA<SaicApiException>()));
    });
  });
}
