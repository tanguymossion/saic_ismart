/// Data model representing a vehicle associated with an iSmart account.
///
/// Returned by `GET /vehicle/list` and used as a key for subsequent
/// telemetry and control requests.
///
/// Source: `api/vehicle/schema.py:VinInfo`
library;

/// A single entry in the vehicle model configuration array.
///
/// Used to detect optional hardware features (e.g. sunroof, heated seats)
/// and battery chemistry. Retrieve items with [Vehicle.getConfigItem].
///
/// Source: `api/vehicle/schema.py:VehicleModelConfiguration`
class VehicleModelConfigItem {
  /// Machine-readable feature code (e.g. `"S35"`, `"HeatedSeat"`, `"BType"`).
  final String itemCode;

  /// Human-readable feature name as returned by the API.
  final String itemName;

  /// Feature value, or `null` if absent in the response.
  final String? itemValue;

  /// Creates a [VehicleModelConfigItem].
  const VehicleModelConfigItem({
    required this.itemCode,
    required this.itemName,
    this.itemValue,
  });

  /// Parses a [VehicleModelConfigItem] from a JSON map.
  factory VehicleModelConfigItem.fromJson(Map<String, dynamic> json) =>
      VehicleModelConfigItem(
        itemCode: json['itemCode'] as String,
        itemName: json['itemName'] as String? ?? '',
        itemValue: json['itemValue'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is VehicleModelConfigItem &&
      itemCode == other.itemCode &&
      itemName == other.itemName &&
      itemValue == other.itemValue;

  @override
  int get hashCode => Object.hash(itemCode, itemName, itemValue);
}

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

  /// Model series code returned by the API (e.g. `"ZP22 EU"`, `"EH32"`), or
  /// `null` if absent.
  ///
  /// Used to infer powertrain type — see [VehicleFeatures.isElectricVehicle].
  final String? series;

  /// Hardware feature and configuration items returned by the API.
  ///
  /// Use [getConfigItem] to query a specific feature by its code. Known codes:
  /// - `"S35"` — sunroof presence: `"0"` = absent, any other value = present
  /// - `"HeatedSeat"` — `"1"` = level-controlled, `"2"` = on/off only
  /// - `"BType"` — battery chemistry: `"1"` = NMC (target SoC configurable)
  final List<VehicleModelConfigItem> vehicleModelConfiguration;

  // ignore: public_member_api_docs
  const Vehicle({
    required this.vin,
    required this.modelName,
    this.modelYear,
    this.brandName,
    this.vehicleName,
    this.series,
    this.vehicleModelConfiguration = const [],
  });

  /// Parses a [Vehicle] from a JSON map returned by `GET /vehicle/list`.
  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        vin: json['vin'] as String,
        modelName: json['modelName'] as String? ?? '',
        modelYear: json['modelYear'] as String?,
        brandName: json['brandName'] as String?,
        vehicleName: json['vehicleName'] as String?,
        series: json['series'] as String?,
        vehicleModelConfiguration:
            (json['vehicleModelConfiguration'] as List<dynamic>? ?? [])
                .map((e) =>
                    VehicleModelConfigItem.fromJson(e as Map<String, dynamic>))
                .toList(),
      );

  /// Returns the first [VehicleModelConfigItem] whose [VehicleModelConfigItem.itemCode]
  /// matches [itemCode], or `null` if no matching item exists.
  VehicleModelConfigItem? getConfigItem(String itemCode) =>
      vehicleModelConfiguration
          .where((item) => item.itemCode == itemCode)
          .firstOrNull;
}
