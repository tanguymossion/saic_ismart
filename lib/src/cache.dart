/// Per-VIN vehicle-status cache with a configurable cooldown TTL.
///
/// The iSmart server processes status requests asynchronously and imposes an
/// implicit cooldown between polls. This cache prevents redundant HTTP calls
/// within the TTL window and preserves the last known value for callers.
library;

import 'models/vehicle_status.dart';

typedef _Entry = ({VehicleStatus status, DateTime fetchedAt});

/// Stores the last [VehicleStatus] per VIN and enforces a fetch cooldown.
///
/// Inject a custom [clock] in tests to control time without sleeping.
///
/// ```dart
/// final cache = SaicCache();
/// cache.set('VIN1', status);
/// final cached = cache.get('VIN1'); // non-null within TTL
/// ```
class SaicCache {
  /// How long a cached entry is considered fresh. Defaults to 600 s.
  final Duration ttl;

  /// Returns the current time. Overridable for deterministic unit tests.
  final DateTime Function() _clock;

  final Map<String, _Entry> _entries = {};

  // ignore: public_member_api_docs
  SaicCache({
    this.ttl = const Duration(seconds: 600),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Returns the cached [VehicleStatus] for [vin] if its age is less than
  /// [ttl], or `null` if the entry is absent or stale.
  VehicleStatus? get(String vin) {
    final entry = _entries[vin];
    if (entry == null) return null;
    if (_clock().difference(entry.fetchedAt) >= ttl) return null;
    return entry.status;
  }

  /// Stores [status] for [vin], stamped with the current clock time.
  void set(String vin, VehicleStatus status) {
    _entries[vin] = (status: status, fetchedAt: _clock());
  }

  /// Returns `true` if a fresh (within [ttl]) entry exists for [vin].
  ///
  /// When this returns `true`, [get] is guaranteed to return a non-null value.
  bool isCoolingDown(String vin) => get(vin) != null;

  /// Removes all cached entries.
  void clear() => _entries.clear();

  /// Removes the cached entry for [vin], if any.
  void clearFor(String vin) => _entries.remove(vin);
}
