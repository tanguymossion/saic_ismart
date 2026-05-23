/// Data model for real-time vehicle telemetry from the iSmart API.
library;

/// A snapshot of a vehicle's current status and sensor readings.
///
/// Includes battery/fuel state, GPS position, door/lock state,
/// and climate information where supported by the vehicle.
class VehicleStatus {
  /// VIN of the vehicle this status belongs to.
  final String vin;

  /// Battery state-of-charge in percent (0–100), or null for ICE vehicles.
  final double? batteryPercent;

  /// Estimated remaining range in kilometres.
  final double? rangeKm;

  // ignore: public_member_api_docs
  const VehicleStatus({
    required this.vin,
    this.batteryPercent,
    this.rangeKm,
  });
}
