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
