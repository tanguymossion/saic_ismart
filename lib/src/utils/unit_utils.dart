// Raw API units → human-readable values.
// Sentinel -128 means "not available" for integer sensor fields.

/// Converts raw mileage (decameters — tens of metres) to kilometres.
///
/// Confirmed: raw `243790` → `24379 km` on MG3 Hybrid EU (`243790 / 10`).
double mileageToKm(int raw) => raw / 10.0;

/// Converts raw mileage (decameters — tens of metres) to miles.
double mileageToMiles(int raw) => raw / 10.0 * 0.621371;

/// Converts raw fuel range (decameters — tens of metres) to kilometres.
///
/// Same unit as mileage. Confirmed: raw `3870` → `387 km` on MG3 Hybrid EU.
double fuelRangeToKm(int raw) => raw / 10.0;

/// Returns `null` when [raw] is the -128 sentinel, otherwise returns [raw].
int? temperatureCelsius(int raw) => raw == -128 ? null : raw;

// Tyre pressure: raw unit is PSI × 2 (confirmed from MG3 Hybrid EU real-world
// values: raw 69/70/65/61 → 34.5/35.0/32.5/30.5 PSI = 2.38/2.41/2.24/2.10 bar,
// consistent with the MG3 recommended 2.3 bar / 33 PSI).
// Sentinels: -128 = not available; 0 = no sensor / no reading.

/// Converts raw tyre pressure (PSI × 2) to bar. Returns `null` for sentinels.
double? tyrePressureToBar(int raw) {
  if (raw == -128 || raw == 0) return null;
  return raw / 2.0 * 0.0689476;
}

/// Converts raw tyre pressure (PSI × 2) to kPa. Returns `null` for sentinels.
double? tyrePressureToKpa(int raw) {
  if (raw == -128 || raw == 0) return null;
  return raw / 2.0 * 6.89476;
}

/// Converts raw tyre pressure (PSI × 2) to PSI. Returns `null` for sentinels.
double? tyrePressureToPsi(int raw) {
  if (raw == -128 || raw == 0) return null;
  return raw / 2.0;
}

/// Returns `null` when [raw] is the -128 sentinel, otherwise returns [raw].
int? batteryVoltageSensor(int raw) => raw == -128 ? null : raw;
