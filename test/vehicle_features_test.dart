import 'package:saic_ismart/src/models/vehicle.dart';
import 'package:saic_ismart/src/models/vehicle_features.dart';
import 'package:test/test.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Vehicle _vehicle(List<Map<String, dynamic>> config, {String? series}) =>
    Vehicle(
      vin: 'VIN',
      modelName: 'Test',
      series: series,
      vehicleModelConfiguration: config
          .map(VehicleModelConfigItem.fromJson)
          .toList(),
    );

const _mg3Config = [
  {'itemCode': 'S35', 'itemName': 'Sunroof', 'itemValue': '0'},
  {'itemCode': 'HeatedSeat', 'itemName': 'Heated Seat', 'itemValue': '2'},
  {'itemCode': 'AC', 'itemName': 'Remote Climate', 'itemValue': '1'},
  {'itemCode': 'S61', 'itemName': 'Remote Sunroof', 'itemValue': '1'},
];

const _evConfig = [
  {'itemCode': 'S35', 'itemName': 'Sunroof', 'itemValue': '1'},
  {'itemCode': 'HeatedSeat', 'itemName': 'Heated Seat', 'itemValue': '1'},
  {'itemCode': 'AC', 'itemName': 'Remote Climate', 'itemValue': '1'},
  {'itemCode': 'S61', 'itemName': 'Remote Sunroof', 'itemValue': '1'},
];

const _mg3EuDoorWindowConfig = [
  {'itemCode': 'DOOR', 'itemName': 'Door Status', 'itemValue': '1111'},
  {'itemCode': 'WINDOW', 'itemName': 'Window Status', 'itemValue': '1000'},
];

const _mg3EuHardwareConfig = [
  {'itemCode': 'BONNUT', 'itemName': 'Bonnet Status', 'itemValue': '0'},
  {'itemCode': 'BOOT', 'itemName': 'Boot Status', 'itemValue': '1'},
  {'itemCode': 'ENGINE', 'itemName': 'Engine Status', 'itemValue': '1'},
  {'itemCode': 'BTKEY', 'itemName': 'Bluetooth Key', 'itemValue': '0'},
  {'itemCode': 'LRD', 'itemName': 'Left-Right Driving', 'itemValue': '0'},
];

const _mg3EuSensorConfig = [
  {'itemCode': 'J17', 'itemName': 'Tire pressure monitoring system', 'itemValue': '1'},
  {'itemCode': 'EXTEMP', 'itemName': 'Exterior Temperature', 'itemValue': '0'},
  {'itemCode': 'INTEMP', 'itemName': 'Interior Temperature', 'itemValue': '1'},
  {'itemCode': 'BATTERY', 'itemName': 'Battery Voltage', 'itemValue': '1'},
  {'itemCode': 'KEYPOS', 'itemName': 'Key Position', 'itemValue': '1'},
];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── MG3 profile ──────────────────────────────────────────────────────────────

  group('VehicleFeatures — MG3 (S35="0", HeatedSeat="2", AC="1", S61="1")',
      () {
    late VehicleFeatures f;

    setUp(() => f = VehicleFeatures(_vehicle(_mg3Config)));

    test('hasSunroof is false — S35="0"', () => expect(f.hasSunroof, false));

    test('heatedSeatCapability is onOffOnly — HeatedSeat="2"',
        () => expect(f.heatedSeatCapability, HeatedSeatCapability.onOffOnly));

    test('hasRemoteClimate is true — AC="1"',
        () => expect(f.hasRemoteClimate, true));

    test('hasRemoteControlledSunroof is false — no sunroof despite S61="1"',
        () => expect(f.hasRemoteControlledSunroof, false));
  });

  // ── EV profile with sunroof ───────────────────────────────────────────────────

  group(
      'VehicleFeatures — EV with sunroof (S35="1", HeatedSeat="1", AC="1", S61="1")',
      () {
    late VehicleFeatures f;

    setUp(() => f = VehicleFeatures(_vehicle(_evConfig)));

    test('hasSunroof is true — S35="1"', () => expect(f.hasSunroof, true));

    test('heatedSeatCapability is multiLevel — HeatedSeat="1"',
        () => expect(f.heatedSeatCapability, HeatedSeatCapability.multiLevel));

    test('hasRemoteClimate is true',
        () => expect(f.hasRemoteClimate, true));

    test('hasRemoteControlledSunroof is true — hasSunroof and S61="1"',
        () => expect(f.hasRemoteControlledSunroof, true));
  });

  // ── Empty config ──────────────────────────────────────────────────────────────

  group('VehicleFeatures — empty config', () {
    late VehicleFeatures f;

    setUp(() => f = VehicleFeatures(_vehicle([])));

    test('hasSunroof is false', () => expect(f.hasSunroof, false));

    test('heatedSeatCapability is none',
        () => expect(f.heatedSeatCapability, HeatedSeatCapability.none));

    test('hasRemoteClimate is false',
        () => expect(f.hasRemoteClimate, false));

    test('hasRemoteControlledSunroof is false',
        () => expect(f.hasRemoteControlledSunroof, false));
  });

  // ── Edge cases ────────────────────────────────────────────────────────────────

  group('VehicleFeatures — edge cases', () {
    test('hasSunroof is false when S35 item is absent', () {
      final f = VehicleFeatures(_vehicle([
        {'itemCode': 'AC', 'itemName': 'AC', 'itemValue': '1'},
      ]));
      expect(f.hasSunroof, false);
    });

    test('hasRemoteControlledSunroof is false when S61 absent but S35 present',
        () {
      final f = VehicleFeatures(_vehicle([
        {'itemCode': 'S35', 'itemName': 'Sunroof', 'itemValue': '1'},
      ]));
      expect(f.hasRemoteControlledSunroof, false);
    });

    test('heatedSeatCapability is none for unrecognised itemValue', () {
      final f = VehicleFeatures(_vehicle([
        {'itemCode': 'HeatedSeat', 'itemName': 'Heated Seat', 'itemValue': '9'},
      ]));
      expect(f.heatedSeatCapability, HeatedSeatCapability.none);
    });
  });

  // ── Door and window sensors ───────────────────────────────────────────────────

  group('VehicleFeatures — door and window sensors (MG3 EU profile)', () {
    late VehicleFeatures f;

    setUp(() => f = VehicleFeatures(_vehicle(_mg3EuDoorWindowConfig)));

    test('doorSensorCount is 4 — DOOR="1111"',
        () => expect(f.doorSensorCount, 4));

    test('windowSensorCount is 1 — WINDOW="1000"',
        () => expect(f.windowSensorCount, 1));
  });

  group('VehicleFeatures — door and window sensors (edge cases)', () {
    test('doorSensorCount is 3 — DOOR="1110"', () {
      final f = VehicleFeatures(_vehicle([
        {'itemCode': 'DOOR', 'itemName': 'Door Status', 'itemValue': '1110'},
      ]));
      expect(f.doorSensorCount, 3);
    });

    test('windowSensorCount is 0 — WINDOW="0000"', () {
      final f = VehicleFeatures(_vehicle([
        {'itemCode': 'WINDOW', 'itemName': 'Window Status', 'itemValue': '0000'},
      ]));
      expect(f.windowSensorCount, 0);
    });

    test('doorSensorCount is 0 — absent', () {
      expect(VehicleFeatures(_vehicle([])).doorSensorCount, 0);
    });

    test('windowSensorCount is 0 — absent', () {
      expect(VehicleFeatures(_vehicle([])).windowSensorCount, 0);
    });
  });

  // ── Hardware presence — MG3 EU profile ───────────────────────────────────────

  group('VehicleFeatures — hardware presence (MG3 EU profile)', () {
    late VehicleFeatures f;

    setUp(() => f = VehicleFeatures(_vehicle(_mg3EuHardwareConfig)));

    test('hasBonnet is false — BONNUT="0"',
        () => expect(f.hasBonnet, false));

    test('hasBoot is true — BOOT="1"',
        () => expect(f.hasBoot, true));

    test('hasEngine is true — ENGINE="1"',
        () => expect(f.hasEngine, true));

    test('hasBluetoothKey is false — BTKEY="0"',
        () => expect(f.hasBluetoothKey, false));

    test('isRightHandDrive is false — LRD="0"',
        () => expect(f.isRightHandDrive, false));

    test('isLeftHandDrive is true — LRD="0"',
        () => expect(f.isLeftHandDrive, true));
  });

  // ── Hardware presence — empty config ──────────────────────────────────────────

  group('VehicleFeatures — hardware presence (empty config)', () {
    late VehicleFeatures f;

    setUp(() => f = VehicleFeatures(_vehicle([])));

    test('hasBonnet is false', () => expect(f.hasBonnet, false));
    test('hasBoot is false', () => expect(f.hasBoot, false));
    test('hasEngine is false', () => expect(f.hasEngine, false));
    test('hasBluetoothKey is false', () => expect(f.hasBluetoothKey, false));
    test('isRightHandDrive is false', () => expect(f.isRightHandDrive, false));
    test('isLeftHandDrive is true', () => expect(f.isLeftHandDrive, true));
  });

  // ── Sensor presence — MG3 EU profile ─────────────────────────────────────────

  group('VehicleFeatures — sensor presence (MG3 EU profile)', () {
    late VehicleFeatures f;

    setUp(() => f = VehicleFeatures(_vehicle(_mg3EuSensorConfig)));

    test('hasTyrePressureMonitoring is true — J17="1"',
        () => expect(f.hasTyrePressureMonitoring, true));

    test('hasExteriorTemperatureSensor is false — EXTEMP="0"',
        () => expect(f.hasExteriorTemperatureSensor, false));

    test('hasInteriorTemperatureSensor is true — INTEMP="1"',
        () => expect(f.hasInteriorTemperatureSensor, true));

    test('hasBatteryVoltageSensor is true — BATTERY="1"',
        () => expect(f.hasBatteryVoltageSensor, true));

    test('hasKeyPositionSensor is true — KEYPOS="1"',
        () => expect(f.hasKeyPositionSensor, true));
  });

  // ── Sensor presence — empty config ────────────────────────────────────────────

  group('VehicleFeatures — sensor presence (empty config)', () {
    late VehicleFeatures f;

    setUp(() => f = VehicleFeatures(_vehicle([])));

    test('hasTyrePressureMonitoring is false',
        () => expect(f.hasTyrePressureMonitoring, false));

    test('hasExteriorTemperatureSensor is false',
        () => expect(f.hasExteriorTemperatureSensor, false));

    test('hasInteriorTemperatureSensor is false',
        () => expect(f.hasInteriorTemperatureSensor, false));

    test('hasBatteryVoltageSensor is false',
        () => expect(f.hasBatteryVoltageSensor, false));

    test('hasKeyPositionSensor is false',
        () => expect(f.hasKeyPositionSensor, false));
  });

  // ── isElectricVehicle ─────────────────────────────────────────────────────────

  group('VehicleFeatures.isElectricVehicle', () {
    bool? ev(String? series) =>
        VehicleFeatures(_vehicle([], series: series)).isElectricVehicle;

    test('ZP22 EU → false (confirmed ICE/hybrid)', () => expect(ev('ZP22 EU'), false));
    test('ZP22 → false (prefix match)', () => expect(ev('ZP22'), false));
    test('EH32 → true', () => expect(ev('EH32'), true));
    test('EV01 → true', () => expect(ev('EV01'), true));
    test('MG4 → true', () => expect(ev('MG4'), true));
    test('null series → null', () => expect(ev(null), isNull));
  });

  // ── Vehicle.features extension getter ────────────────────────────────────────

  group('Vehicle.features extension', () {
    test('returns a VehicleFeatures wrapping the same vehicle', () {
      final v = _vehicle(_mg3Config);
      expect(v.features, isA<VehicleFeatures>());
      expect(v.features.vehicle, same(v));
    });

    test('vehicle.features.hasSunroof matches direct VehicleFeatures(vehicle)',
        () {
      final v = _vehicle(_evConfig);
      expect(v.features.hasSunroof, VehicleFeatures(v).hasSunroof);
    });
  });
}
