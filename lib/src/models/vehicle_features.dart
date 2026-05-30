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
