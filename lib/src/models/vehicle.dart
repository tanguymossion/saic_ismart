/// Data model representing a vehicle associated with an iSmart account.
library;

/// A vehicle registered to an iSmart user account.
///
/// Returned by the vehicle-list endpoint and used as a key for
/// subsequent telemetry and control requests.
class Vehicle {
  /// Unique vehicle identification number (VIN).
  final String vin;

  /// Human-readable model name (e.g. "MG ZS EV").
  final String modelName;

  // ignore: public_member_api_docs
  const Vehicle({required this.vin, required this.modelName});
}
