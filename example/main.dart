/// Example showing the planned saic_ismart API usage.
///
/// This file documents intended usage only — no implementation exists yet.
library;

// ignore_for_file: unused_local_variable

import 'package:saic_ismart/saic_ismart.dart';

Future<void> main() async {
  // 1. Create a client (region defaults to EU).
  final client = SaicClient(
    SaicConfig(username: 'user@example.com', password: 's3cr3t'),
  );

  // 2. Authenticate with iSmart credentials.
  // await client.login();

  // 3. List vehicles linked to the account.
  // final vehicles = await client.getVehicles();

  // 4. Fetch real-time status for the first vehicle.
  // final status = await client.getVehicleStatus(vin: vehicles.first.vin);
  // print('Battery: ${status.batteryPercent}%');
  // print('Range:   ${status.rangeKm} km');

  // 5. Always dispose the client when done.
  // client.dispose();
}
