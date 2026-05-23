// Run with:
// SAIC_USERNAME=you@example.com SAIC_PASSWORD=yourpassword dart run example/main.dart

import 'dart:io';

import 'package:saic_ismart/saic_ismart.dart';

Future<void> main() async {
  final username = Platform.environment['SAIC_USERNAME'];
  final password = Platform.environment['SAIC_PASSWORD'];
  if (username == null || username.isEmpty) {
    stderr.writeln('Error: SAIC_USERNAME environment variable is not set.');
    exit(1);
  }
  if (password == null || password.isEmpty) {
    stderr.writeln('Error: SAIC_PASSWORD environment variable is not set.');
    exit(1);
  }

  final client = SaicClient(
    SaicConfig(username: username, password: password),
  );

  try {
    // ── 1. Login ─────────────────────────────────────────────────────────────
    await client.login();
    print('✓ Logged in as $username, token expires at ${client.session!.tokenExpiration}');

    // ── 2. getVehicles ────────────────────────────────────────────────────────
    final vehicles = await client.getVehicles();
    print('✓ Found ${vehicles.length} vehicle(s)');
    for (final v in vehicles) {
      final brand = v.brandName ?? '';
      final name = v.vehicleName ?? v.modelName;
      final year = v.modelYear != null ? ' ${v.modelYear}' : '';
      print('  - $brand $name$year (VIN: ${v.vin})'.trim());
    }

    if (vehicles.isEmpty) {
      print('No vehicles found — skipping status fetch.');
      return;
    }

    // ── 3. getVehicleStatus for the first vehicle ─────────────────────────────
    final vin = vehicles.first.vin;
    final status = await client.getVehicleStatus(vin);
    final basic = status.basicVehicleStatus;
    final gps = status.gpsPosition;
    final lat = gps?.latitudeDegrees?.toStringAsFixed(6) ?? 'n/a';
    final lon = gps?.longitudeDegrees?.toStringAsFixed(6) ?? 'n/a';

    print('✓ Vehicle status:');
    // lockStatus is a raw int (0 = unlocked, assumed); no isLocked helper exists.
    print('  Locked: ${basic?.lockStatus}');
    print('  Engine running: ${basic?.isEngineRunning}');
    print('  Parked: ${basic?.isParked}');
    print('  Mileage: ${basic?.mileage}');
    print('  Fuel level: ${basic?.fuelLevelPrc}%');
    print('  Location: $lat, $lon');
    print('  GPS status: ${gps?.gpsStatus}');
    print('  Status time: ${status.statusTime}');
  } on SaicSessionConflictException catch (e) {
    stderr.writeln('Session conflict (${e.statusCode}): ${e.message}');
    stderr.writeln('Another client may be using the same credentials. '
        'Wait ~15 minutes before retrying.');
    exit(2);
  } on SaicAuthException catch (e) {
    stderr.writeln('Authentication error (${e.statusCode}): ${e.message}');
    exit(2);
  } on SaicApiException catch (e) {
    stderr.writeln('API error (${e.statusCode}): ${e.message}');
    exit(3);
  } catch (e, st) {
    stderr.writeln('Unexpected error: $e');
    stderr.writeln(st);
    exit(4);
  }
}
