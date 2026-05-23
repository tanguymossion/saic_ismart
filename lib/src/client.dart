/// HTTP client for the SAIC iSmart connected-vehicle API.
///
/// Handles request construction, authentication header injection,
/// and response deserialization for all API endpoints.
library;

// ignore: unused_import
import 'auth.dart';
// ignore: unused_import
import 'exceptions.dart';
// ignore: unused_import
import 'models/vehicle.dart';
// ignore: unused_import
import 'models/vehicle_status.dart';

/// Entry point for interacting with the iSmart API.
///
/// Create an instance with [ISmartClient.new], authenticate via
/// [ISmartClient.login], then call vehicle or telemetry methods.
class ISmartClient {
  // TODO: implement
}
