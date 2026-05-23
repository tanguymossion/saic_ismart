import 'package:saic_ismart/src/utils/unit_utils.dart';
import 'package:saic_ismart/src/models/vehicle_status.dart';
import 'package:test/test.dart';

void main() {
  // ── mileageToKm ───────────────────────────────────────────────────────────────

  group('mileageToKm', () {
    test('converts decimeters to km', () {
      expect(mileageToKm(10000), closeTo(1.0, 1e-9));
      expect(mileageToKm(243790), closeTo(24.379, 1e-6));
    });

    test('zero input returns zero', () {
      expect(mileageToKm(0), 0.0);
    });
  });

  // ── mileageToMiles ────────────────────────────────────────────────────────────

  group('mileageToMiles', () {
    test('converts decimeters to miles', () {
      expect(mileageToMiles(10000), closeTo(0.621371, 1e-6));
    });

    test('zero input returns zero', () {
      expect(mileageToMiles(0), 0.0);
    });
  });

  // ── fuelRangeToKm ─────────────────────────────────────────────────────────────

  group('fuelRangeToKm', () {
    test('converts decimeters to km', () {
      expect(fuelRangeToKm(5000000), closeTo(500.0, 1e-9));
    });

    test('zero input returns zero', () {
      expect(fuelRangeToKm(0), 0.0);
    });
  });

  // ── temperatureCelsius ────────────────────────────────────────────────────────

  group('temperatureCelsius', () {
    test('returns null for sentinel -128', () {
      expect(temperatureCelsius(-128), isNull);
    });

    test('returns value unchanged for normal temperatures', () {
      expect(temperatureCelsius(20), 20);
      expect(temperatureCelsius(0), 0);
      expect(temperatureCelsius(-10), -10);
      expect(temperatureCelsius(40), 40);
    });

    test('-127 is not the sentinel — returns -127', () {
      expect(temperatureCelsius(-127), -127);
    });
  });

  // ── tyrePressureSensor ────────────────────────────────────────────────────────

  group('tyrePressureSensor', () {
    test('returns null for sentinel -128', () {
      expect(tyrePressureSensor(-128), isNull);
    });

    test('returns value unchanged for normal values', () {
      expect(tyrePressureSensor(250), 250);
      expect(tyrePressureSensor(0), 0);
    });
  });

  // ── batteryVoltageSensor ──────────────────────────────────────────────────────

  group('batteryVoltageSensor', () {
    test('returns null for sentinel -128', () {
      expect(batteryVoltageSensor(-128), isNull);
    });

    test('returns value unchanged for normal values', () {
      expect(batteryVoltageSensor(120), 120);
      expect(batteryVoltageSensor(0), 0);
    });
  });

  // ── BasicVehicleStatus getters ────────────────────────────────────────────────

  group('BasicVehicleStatus convenience getters', () {
    BasicVehicleStatus makeStatus({
      int? mileage,
      int? fuelRange,
      int? exteriorTemperature,
      int? interiorTemperature,
      int? batteryVoltage,
    }) =>
        BasicVehicleStatus(
          mileage: mileage,
          fuelRange: fuelRange,
          exteriorTemperature: exteriorTemperature,
          interiorTemperature: interiorTemperature,
          batteryVoltage: batteryVoltage,
        );

    test('mileageKm converts correctly', () {
      expect(makeStatus(mileage: 10000).mileageKm, closeTo(1.0, 1e-9));
    });

    test('mileageKm is null when mileage is null', () {
      expect(makeStatus().mileageKm, isNull);
    });

    test('mileageMiles converts correctly', () {
      expect(makeStatus(mileage: 10000).mileageMiles, closeTo(0.621371, 1e-6));
    });

    test('mileageMiles is null when mileage is null', () {
      expect(makeStatus().mileageMiles, isNull);
    });

    test('fuelRangeKm converts correctly', () {
      expect(makeStatus(fuelRange: 5000000).fuelRangeKm, closeTo(500.0, 1e-9));
    });

    test('fuelRangeKm is null when fuelRange is null', () {
      expect(makeStatus().fuelRangeKm, isNull);
    });

    test('exteriorTemperatureCelsius returns value', () {
      expect(makeStatus(exteriorTemperature: 22).exteriorTemperatureCelsius, 22);
    });

    test('exteriorTemperatureCelsius returns null for -128 sentinel', () {
      expect(
          makeStatus(exteriorTemperature: -128).exteriorTemperatureCelsius, isNull);
    });

    test('exteriorTemperatureCelsius is null when field is null', () {
      expect(makeStatus().exteriorTemperatureCelsius, isNull);
    });

    test('interiorTemperatureCelsius returns value', () {
      expect(makeStatus(interiorTemperature: 18).interiorTemperatureCelsius, 18);
    });

    test('interiorTemperatureCelsius returns null for -128 sentinel', () {
      expect(
          makeStatus(interiorTemperature: -128).interiorTemperatureCelsius, isNull);
    });

    test('interiorTemperatureCelsius is null when field is null', () {
      expect(makeStatus().interiorTemperatureCelsius, isNull);
    });

    test('batteryVoltageValue returns raw value', () {
      expect(makeStatus(batteryVoltage: 120).batteryVoltageValue, 120);
    });

    test('batteryVoltageValue returns null for -128 sentinel', () {
      expect(makeStatus(batteryVoltage: -128).batteryVoltageValue, isNull);
    });

    test('batteryVoltageValue is null when batteryVoltage is null', () {
      expect(makeStatus().batteryVoltageValue, isNull);
    });
  });
}
