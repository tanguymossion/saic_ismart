/// Dart client for the SAIC iSmart connected-vehicle API.
///
/// Supports MG, Roewe, and Maxus/LDV vehicles. Import this library
/// to access [ISmartClient], the primary entry point.
///
/// ```dart
/// import 'package:saic_ismart/saic_ismart.dart';
///
/// final client = ISmartClient();
/// await client.login(username: 'user@example.com', password: 's3cr3t');
/// final vehicles = await client.getVehicles();
/// ```
library saic_ismart;

export 'src/auth.dart';
export 'src/client.dart';
export 'src/exceptions.dart';
export 'src/models/vehicle.dart';
export 'src/models/vehicle_status.dart';
