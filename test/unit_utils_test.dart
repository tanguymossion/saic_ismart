import 'package:saic_ismart/src/utils/unit_utils.dart';
import 'package:saic_ismart/src/models/vehicle_status.dart';
import 'package:test/test.dart';

void main() {
  // ── mileageToKm ───────────────────────────────────────────────────────────────

  group('mileageToKm', () {
    test('converts decameters to km', () {
      expect(mileageToKm(10), closeTo(1.0, 1e-9));
      expect(mileageToKm(243790), closeTo(24379.0, 1e-6));
    });

    test('zero input returns zero', () {
      expect(mileageToKm(0), 0.0);
    });
  });

  // ── mileageToMiles ────────────────────────────────────────────────────────────

  group('mileageToMiles', () {
    test('converts decameters to miles', () {
      expect(mileageToMiles(10), closeTo(0.621371, 1e-6));
    });

    test('zero input returns zero', () {
      expect(mileageToMiles(0), 0.0);
    });
  });

  // ── fuelRangeToKm ─────────────────────────────────────────────────────────────

  group('fuelRangeToKm', () {
    test('converts decameters to km', () {
      expect(fuelRangeToKm(5000), closeTo(500.0, 1e-9));
      expect(fuelRangeToKm(3870), closeTo(387.0, 1e-9));
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

  // ── tyrePressureToBar ─────────────────────────────────────────────────────────

  group('tyrePressureToBar', () {
    test('returns null for sentinel -128',
        () => expect(tyrePressureToBar(-128), isNull));
    test('returns null for sentinel 0',
        () => expect(tyrePressureToBar(0), isNull));
    test('converts raw 69 → ~2.38 bar (MG3 FL real-world)',
        () => expect(tyrePressureToBar(69), closeTo(2.378, 0.001)));
    test('converts raw 70 → ~2.41 bar (MG3 FR real-world)',
        () => expect(tyrePressureToBar(70), closeTo(2.413, 0.001)));
    test('converts raw 65 → ~2.24 bar (MG3 RL real-world)',
        () => expect(tyrePressureToBar(65), closeTo(2.241, 0.001)));
    test('converts raw 61 → ~2.10 bar (MG3 RR real-world)',
        () => expect(tyrePressureToBar(61), closeTo(2.103, 0.001)));
  });

  // ── tyrePressureToKpa ─────────────────────────────────────────────────────────

  group('tyrePressureToKpa', () {
    test('returns null for sentinel -128',
        () => expect(tyrePressureToKpa(-128), isNull));
    test('returns null for sentinel 0',
        () => expect(tyrePressureToKpa(0), isNull));
    test('converts raw 69 → ~237.8 kPa',
        () => expect(tyrePressureToKpa(69), closeTo(237.77, 0.1)));
  });

  // ── tyrePressureToPsi ─────────────────────────────────────────────────────────

  group('tyrePressureToPsi', () {
    test('returns null for sentinel -128',
        () => expect(tyrePressureToPsi(-128), isNull));
    test('returns null for sentinel 0',
        () => expect(tyrePressureToPsi(0), isNull));
    test('converts raw 69 → 34.5 PSI',
        () => expect(tyrePressureToPsi(69), closeTo(34.5, 1e-9)));
    test('converts raw 66 → 33.0 PSI',
        () => expect(tyrePressureToPsi(66), closeTo(33.0, 1e-9)));
  });

  // ── batteryVoltageToVolts ─────────────────────────────────────────────────────

  group('batteryVoltageToVolts', () {
    test('returns null for sentinel -128', () {
      expect(batteryVoltageToVolts(-128), isNull);
    });

    test('converts raw to volts (× 0.1)', () {
      expect(batteryVoltageToVolts(127), closeTo(12.7, 1e-9));
      expect(batteryVoltageToVolts(120), closeTo(12.0, 1e-9));
      expect(batteryVoltageToVolts(0), closeTo(0.0, 1e-9));
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
      int? frontLeftTyrePressure,
      int? frontRightTyrePressure,
      int? rearLeftTyrePressure,
      int? rearRightTyrePressure,
    }) =>
        BasicVehicleStatus(
          mileage: mileage,
          fuelRange: fuelRange,
          exteriorTemperature: exteriorTemperature,
          interiorTemperature: interiorTemperature,
          batteryVoltage: batteryVoltage,
          frontLeftTyrePressure: frontLeftTyrePressure,
          frontRightTyrePressure: frontRightTyrePressure,
          rearLeftTyrePressure: rearLeftTyrePressure,
          rearRightTyrePressure: rearRightTyrePressure,
        );

    test('mileageKm converts correctly', () {
      expect(makeStatus(mileage: 10).mileageKm, closeTo(1.0, 1e-9));
    });

    test('mileageKm is null when mileage is null', () {
      expect(makeStatus().mileageKm, isNull);
    });

    test('mileageMiles converts correctly', () {
      expect(makeStatus(mileage: 10).mileageMiles, closeTo(0.621371, 1e-6));
    });

    test('mileageMiles is null when mileage is null', () {
      expect(makeStatus().mileageMiles, isNull);
    });

    test('fuelRangeKm converts correctly', () {
      expect(makeStatus(fuelRange: 5000).fuelRangeKm, closeTo(500.0, 1e-9));
    });

    test('fuelRangeKm is null when fuelRange is null', () {
      expect(makeStatus().fuelRangeKm, isNull);
    });

    test('exteriorTemperatureCelsius returns value', () {
      expect(
          makeStatus(exteriorTemperature: 22).exteriorTemperatureCelsius, 22);
    });

    test('exteriorTemperatureCelsius returns null for -128 sentinel', () {
      expect(makeStatus(exteriorTemperature: -128).exteriorTemperatureCelsius,
          isNull);
    });

    test('exteriorTemperatureCelsius is null when field is null', () {
      expect(makeStatus().exteriorTemperatureCelsius, isNull);
    });

    test('interiorTemperatureCelsius returns value', () {
      expect(
          makeStatus(interiorTemperature: 18).interiorTemperatureCelsius, 18);
    });

    test('interiorTemperatureCelsius returns null for -128 sentinel', () {
      expect(makeStatus(interiorTemperature: -128).interiorTemperatureCelsius,
          isNull);
    });

    test('interiorTemperatureCelsius is null when field is null', () {
      expect(makeStatus().interiorTemperatureCelsius, isNull);
    });

    test('batteryVoltageVolts converts raw to volts', () {
      expect(makeStatus(batteryVoltage: 127).batteryVoltageVolts,
          closeTo(12.7, 1e-9));
      expect(makeStatus(batteryVoltage: 120).batteryVoltageVolts,
          closeTo(12.0, 1e-9));
    });

    test('batteryVoltageVolts returns null for -128 sentinel', () {
      expect(makeStatus(batteryVoltage: -128).batteryVoltageVolts, isNull);
    });

    test('batteryVoltageVolts is null when batteryVoltage is null', () {
      expect(makeStatus().batteryVoltageVolts, isNull);
    });

    test(
        'frontLeftTyrePressureBar converts MG3 real-world value (raw=69→~2.38 bar)',
        () => expect(
            makeStatus(frontLeftTyrePressure: 69).frontLeftTyrePressureBar,
            closeTo(2.378, 0.001)));
    test('frontLeftTyrePressureBar null when field is null',
        () => expect(makeStatus().frontLeftTyrePressureBar, isNull));
    test(
        'frontLeftTyrePressureBar null for sentinel 0',
        () => expect(
            makeStatus(frontLeftTyrePressure: 0).frontLeftTyrePressureBar,
            isNull));
    test(
        'frontLeftTyrePressureBar null for sentinel -128',
        () => expect(
            makeStatus(frontLeftTyrePressure: -128).frontLeftTyrePressureBar,
            isNull));

    test(
        'frontRightTyrePressureBar converts MG3 real-world value (raw=70→~2.41 bar)',
        () => expect(
            makeStatus(frontRightTyrePressure: 70).frontRightTyrePressureBar,
            closeTo(2.413, 0.001)));

    test(
        'rearLeftTyrePressureBar converts MG3 real-world value (raw=65→~2.24 bar)',
        () => expect(
            makeStatus(rearLeftTyrePressure: 65).rearLeftTyrePressureBar,
            closeTo(2.241, 0.001)));

    test(
        'rearRightTyrePressureBar converts MG3 real-world value (raw=61→~2.10 bar)',
        () => expect(
            makeStatus(rearRightTyrePressure: 61).rearRightTyrePressureBar,
            closeTo(2.103, 0.001)));
  });
}
