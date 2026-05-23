// Raw API units → human-readable values.
// Sentinel -128 means "not available" for integer sensor fields.

/// Converts raw mileage (decimeters) to kilometres.
double mileageToKm(int raw) => raw / 10000;

/// Converts raw mileage (decimeters) to miles.
double mileageToMiles(int raw) => raw / 10000 * 0.621371;

/// Converts raw fuel range (decimeters) to kilometres.
double fuelRangeToKm(int raw) => raw / 10000;

/// Returns `null` when [raw] is the -128 sentinel, otherwise returns [raw].
int? temperatureCelsius(int raw) => raw == -128 ? null : raw;

/// Returns `null` when [raw] is the -128 sentinel, otherwise returns [raw].
int? tyrePressureSensor(int raw) => raw == -128 ? null : raw;

/// Returns `null` when [raw] is the -128 sentinel, otherwise returns [raw].
int? batteryVoltageSensor(int raw) => raw == -128 ? null : raw;
