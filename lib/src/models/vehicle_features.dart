/// Feature-detection helpers derived from [Vehicle.vehicleModelConfiguration].
///
/// Import via the package barrel or use [Vehicle.features] (available when
/// `package:saic_ismart/saic_ismart.dart` is imported).
library;

import 'vehicle.dart';

/// Heated seat capability level for a vehicle.
enum HeatedSeatCapability {
  /// No heated seat data in the vehicle configuration.
  none,

  /// Heated seats with a binary on/off toggle only (`HeatedSeat itemValue == "2"`).
  onOffOnly,

  /// Heated seats with four levels: off / low / medium / high (`HeatedSeat itemValue == "1"`).
  multiLevel,
}

/// Feature-detection wrapper around a [Vehicle].
///
/// All accessors return `false` / [HeatedSeatCapability.none] when the
/// relevant configuration item is absent — i.e. unknown is treated as
/// unsupported for safety.
///
/// ```dart
/// final features = vehicle.features;
/// if (features.hasSunroof) { ... }
/// ```
class VehicleFeatures {
  // ignore: public_member_api_docs
  const VehicleFeatures(this.vehicle);

  /// The vehicle whose configuration is being queried.
  final Vehicle vehicle;

  /// Whether the vehicle has a sunroof.
  ///
  /// Based on `vehicleModelConfiguration` item `S35`:
  /// - `"0"` → no sunroof
  /// - any other value → sunroof present
  /// - item absent → `false` (unknown treated as unsupported)
  bool get hasSunroof {
    final item = vehicle.getConfigItem('S35');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Heated seat capability for this vehicle.
  ///
  /// Based on `vehicleModelConfiguration` item `HeatedSeat`:
  /// - `"1"` → [HeatedSeatCapability.multiLevel]
  /// - `"2"` → [HeatedSeatCapability.onOffOnly]
  /// - absent or other → [HeatedSeatCapability.none]
  HeatedSeatCapability get heatedSeatCapability {
    final value = vehicle.getConfigItem('HeatedSeat')?.itemValue;
    return switch (value) {
      '1' => HeatedSeatCapability.multiLevel,
      '2' => HeatedSeatCapability.onOffOnly,
      _ => HeatedSeatCapability.none,
    };
  }

  /// Whether the vehicle supports remote climate control.
  ///
  /// Based on `vehicleModelConfiguration` item `AC` with `itemValue == "1"`.
  bool get hasRemoteClimate =>
      vehicle.getConfigItem('AC')?.itemValue == '1';

  /// Whether the vehicle has airbags (regular airbags, item code `Q00`).
  ///
  /// Based on `vehicleModelConfiguration` item `Q00` with `itemValue != "0"`.
  bool get hasAirbags {
    final item = vehicle.getConfigItem('Q00');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle reports energy state.
  ///
  /// Based on `vehicleModelConfiguration` item `ENERGY` with `itemValue != "0"`.
  bool get hasEnergyState {
    final item = vehicle.getConfigItem('ENERGY');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Official EV flag from the SAIC API (`EV` item code).
  ///
  /// Returns `null` if the item is absent — not all vehicles include this flag.
  /// See also [isElectricVehicle] which uses the Python-validated ZP22 series
  /// rule as a fallback.
  bool? get hasElectricVehicleFlag {
    final item = vehicle.getConfigItem('EV');
    if (item == null) return null;
    return item.itemValue != '0';
  }

  /// Whether this vehicle is electric or electrified (BEV or PHEV).
  ///
  /// Based on the Python MQTT client's validated rule: series starting with
  /// `"ZP22"` are ICE/hybrid (confirmed MG3 Hybrid EU); everything else is
  /// considered electric or electrified. Cannot distinguish BEV from PHEV —
  /// no validated series prefix exists yet.
  ///
  /// Returns `null` when [Vehicle.series] is absent.
  bool? get isElectricVehicle {
    final s = vehicle.series;
    if (s == null) return null;
    return !s.startsWith('ZP22');
  }

  /// Number of door sensors reported by the vehicle.
  ///
  /// Based on `vehicleModelConfiguration` item `DOOR` — each `'1'` character
  /// in the bitmask string represents one door sensor. MG3 EU returns `"1111"`
  /// = 4 doors. Returns `0` if the item is absent.
  int get doorSensorCount =>
      vehicle.getConfigItem('DOOR')?.itemValue?.split('').where((c) => c == '1').length ?? 0;

  /// Number of window sensors reported by the vehicle.
  ///
  /// Based on `vehicleModelConfiguration` item `WINDOW` — each `'1'` character
  /// in the bitmask string represents one window sensor. MG3 EU returns `"1000"`
  /// = 1 window sensor (driver only). Returns `0` if the item is absent.
  int get windowSensorCount =>
      vehicle.getConfigItem('WINDOW')?.itemValue?.split('').where((c) => c == '1').length ?? 0;

  /// Whether the vehicle has a bonnet sensor.
  ///
  /// Based on `vehicleModelConfiguration` item `BONNUT` with `itemValue != "0"`.
  bool get hasBonnet {
    final item = vehicle.getConfigItem('BONNUT');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle has a boot/trunk sensor.
  ///
  /// Based on `vehicleModelConfiguration` item `BOOT` with `itemValue != "0"`.
  bool get hasBoot {
    final item = vehicle.getConfigItem('BOOT');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle has an engine status sensor.
  ///
  /// Based on `vehicleModelConfiguration` item `ENGINE` with `itemValue != "0"`.
  bool get hasEngine {
    final item = vehicle.getConfigItem('ENGINE');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle supports Bluetooth key.
  ///
  /// Based on `vehicleModelConfiguration` item `BTKEY` with `itemValue != "0"`.
  bool get hasBluetoothKey {
    final item = vehicle.getConfigItem('BTKEY');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle is right-hand drive.
  ///
  /// Based on `vehicleModelConfiguration` item `LRD` with `itemValue == "1"`.
  /// False means left-hand drive or unknown.
  bool get isRightHandDrive =>
      vehicle.getConfigItem('LRD')?.itemValue == '1';

  /// Whether the vehicle is left-hand drive.
  ///
  /// Inverse of [isRightHandDrive].
  bool get isLeftHandDrive => !isRightHandDrive;

  /// Whether the vehicle has a tyre pressure monitoring system (TPMS).
  ///
  /// Based on `vehicleModelConfiguration` item `J17` with `itemValue != "0"`.
  bool get hasTyrePressureMonitoring {
    final item = vehicle.getConfigItem('J17');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle has an exterior temperature sensor.
  ///
  /// Based on `vehicleModelConfiguration` item `EXTEMP` with `itemValue != "0"`.
  bool get hasExteriorTemperatureSensor {
    final item = vehicle.getConfigItem('EXTEMP');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle has an interior temperature sensor.
  ///
  /// Based on `vehicleModelConfiguration` item `INTEMP` with `itemValue != "0"`.
  bool get hasInteriorTemperatureSensor {
    final item = vehicle.getConfigItem('INTEMP');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle reports 12V battery voltage.
  ///
  /// Based on `vehicleModelConfiguration` item `BATTERY` with `itemValue != "0"`.
  bool get hasBatteryVoltageSensor {
    final item = vehicle.getConfigItem('BATTERY');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the vehicle reports key position.
  ///
  /// Based on `vehicleModelConfiguration` item `KEYPOS` with `itemValue != "0"`.
  bool get hasKeyPositionSensor {
    final item = vehicle.getConfigItem('KEYPOS');
    if (item == null) return false;
    return item.itemValue != '0';
  }

  /// Whether the sunroof can be operated via remote control.
  ///
  /// Requires both [hasSunroof] and `vehicleModelConfiguration` item `S61`
  /// with `itemValue == "1"`.
  bool get hasRemoteControlledSunroof {
    if (!hasSunroof) return false;
    return vehicle.getConfigItem('S61')?.itemValue == '1';
  }
}

/// Convenience extension that adds [VehicleFeatures] access to [Vehicle].
///
/// Available automatically when `package:saic_ismart/saic_ismart.dart` is
/// imported.
extension VehicleFeaturesExtension on Vehicle {
  /// Returns a [VehicleFeatures] wrapper for this vehicle.
  VehicleFeatures get features => VehicleFeatures(this);
}
