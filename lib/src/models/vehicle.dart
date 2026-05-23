/// Data model representing a vehicle associated with an iSmart account.
///
/// Returned by `GET /vehicle/list` and used as a key for subsequent
/// telemetry and control requests.
///
/// Source: `api/vehicle/schema.py:VinInfo`
library;

/// A vehicle registered to an iSmart user account.
class Vehicle {
  /// Unique vehicle identification number (VIN).
  final String vin;

  /// Human-readable model name (e.g. `"MG ZS EV"`).
  ///
  /// Used to infer powertrain type when no explicit BEV/PHEV flag is present
  /// in the vehicle status response (TECHNICAL_REFERENCE.md §5).
  final String modelName;

  /// Model year string as returned by the API (e.g. `"2023"`), or `null` if
  /// absent from the response.
  final String? modelYear;

  /// Brand name (e.g. `"MG"`, `"Maxus"`, `"Roewe"`), or `null` if absent.
  final String? brandName;

  /// User-facing vehicle nickname set in the iSmart app, or `null` if absent.
  final String? vehicleName;

  // ignore: public_member_api_docs
  const Vehicle({
    required this.vin,
    required this.modelName,
    this.modelYear,
    this.brandName,
    this.vehicleName,
  });

  /// Parses a [Vehicle] from a JSON map returned by `GET /vehicle/list`.
  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        vin: json['vin'] as String,
        modelName: json['modelName'] as String? ?? '',
        modelYear: json['modelYear'] as String?,
        brandName: json['brandName'] as String?,
        vehicleName: json['vehicleName'] as String?,
      );
}
