import 'package:saic_ismart/src/cache.dart';
import 'package:saic_ismart/src/models/vehicle_status.dart';
import 'package:test/test.dart';

// A minimal VehicleStatus fixture — we only need identity for cache tests.
const _statusA = VehicleStatus(statusTime: 1);
const _statusB = VehicleStatus(statusTime: 2);
const _vin1 = 'VIN1';
const _vin2 = 'VIN2';

/// Returns a [SaicCache] whose clock is a mutable [DateTime] that tests
/// can advance without sleeping.
(SaicCache cache, void Function(Duration) advance) _makeCache({
  Duration ttl = const Duration(seconds: 600),
}) {
  var now = DateTime(2024, 6, 1, 12);
  final cache = SaicCache(ttl: ttl, clock: () => now);
  return (cache, (delta) => now = now.add(delta));
}

void main() {
  // ── get ─────────────────────────────────────────────────────────────────────

  group('SaicCache.get', () {
    test('returns null on empty cache', () {
      final (cache, _) = _makeCache();
      expect(cache.get(_vin1), isNull);
    });

    test('returns status immediately after set', () {
      final (cache, _) = _makeCache();
      cache.set(_vin1, _statusA);
      expect(cache.get(_vin1), _statusA);
    });

    test('returns status at TTL boundary (exclusive)', () {
      final (cache, advance) = _makeCache();
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 599));
      expect(cache.get(_vin1), _statusA);
    });

    test('returns null when entry is exactly at TTL', () {
      final (cache, advance) = _makeCache();
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 600));
      expect(cache.get(_vin1), isNull);
    });

    test('returns null when entry is past TTL', () {
      final (cache, advance) = _makeCache();
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 601));
      expect(cache.get(_vin1), isNull);
    });

    test('returns null for unknown VIN even when another VIN is cached', () {
      final (cache, _) = _makeCache();
      cache.set(_vin1, _statusA);
      expect(cache.get(_vin2), isNull);
    });

    test('returns latest value after overwrite', () {
      final (cache, _) = _makeCache();
      cache.set(_vin1, _statusA);
      cache.set(_vin1, _statusB);
      expect(cache.get(_vin1), _statusB);
    });

    test('overwrite resets the TTL clock', () {
      final (cache, advance) = _makeCache();
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 400));
      cache.set(_vin1, _statusB); // reset clock
      advance(const Duration(seconds: 400)); // 400s past the overwrite
      expect(cache.get(_vin1), _statusB);
    });
  });

  // ── isCoolingDown ────────────────────────────────────────────────────────────

  group('SaicCache.isCoolingDown', () {
    test('false when cache is empty', () {
      final (cache, _) = _makeCache();
      expect(cache.isCoolingDown(_vin1), isFalse);
    });

    test('true immediately after set', () {
      final (cache, _) = _makeCache();
      cache.set(_vin1, _statusA);
      expect(cache.isCoolingDown(_vin1), isTrue);
    });

    test('true within TTL window', () {
      final (cache, advance) = _makeCache();
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 599));
      expect(cache.isCoolingDown(_vin1), isTrue);
    });

    test('false at exactly TTL', () {
      final (cache, advance) = _makeCache();
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 600));
      expect(cache.isCoolingDown(_vin1), isFalse);
    });

    test('false after TTL expiry', () {
      final (cache, advance) = _makeCache();
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 601));
      expect(cache.isCoolingDown(_vin1), isFalse);
    });

    test('consistent with get — isCoolingDown iff get is non-null', () {
      final (cache, advance) = _makeCache();
      cache.set(_vin1, _statusA);

      // Within TTL: both agree
      expect(cache.isCoolingDown(_vin1), isTrue);
      expect(cache.get(_vin1), isNotNull);

      // After TTL: both agree
      advance(const Duration(seconds: 601));
      expect(cache.isCoolingDown(_vin1), isFalse);
      expect(cache.get(_vin1), isNull);
    });
  });

  // ── clear / clearFor ─────────────────────────────────────────────────────────

  group('SaicCache.clear', () {
    test('removes all entries', () {
      final (cache, _) = _makeCache();
      cache.set(_vin1, _statusA);
      cache.set(_vin2, _statusB);
      cache.clear();
      expect(cache.get(_vin1), isNull);
      expect(cache.get(_vin2), isNull);
    });

    test('isCoolingDown returns false after clear', () {
      final (cache, _) = _makeCache();
      cache.set(_vin1, _statusA);
      cache.clear();
      expect(cache.isCoolingDown(_vin1), isFalse);
    });

    test('can set new values after clear', () {
      final (cache, _) = _makeCache();
      cache.set(_vin1, _statusA);
      cache.clear();
      cache.set(_vin1, _statusB);
      expect(cache.get(_vin1), _statusB);
    });
  });

  group('SaicCache.clearFor', () {
    test('removes only the targeted VIN', () {
      final (cache, _) = _makeCache();
      cache.set(_vin1, _statusA);
      cache.set(_vin2, _statusB);
      cache.clearFor(_vin1);
      expect(cache.get(_vin1), isNull);
      expect(cache.get(_vin2), _statusB);
    });

    test('clearFor on absent VIN does not throw', () {
      final (cache, _) = _makeCache();
      expect(() => cache.clearFor(_vin1), returnsNormally);
    });
  });

  // ── Custom TTL ───────────────────────────────────────────────────────────────

  group('SaicCache custom TTL', () {
    test('60 s TTL expires after 60 s', () {
      final (cache, advance) = _makeCache(ttl: const Duration(seconds: 60));
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 59));
      expect(cache.isCoolingDown(_vin1), isTrue);
      advance(const Duration(seconds: 1));
      expect(cache.isCoolingDown(_vin1), isFalse);
    });

    test('10 s TTL expires well before default 600 s', () {
      final (cache, advance) = _makeCache(ttl: const Duration(seconds: 10));
      cache.set(_vin1, _statusA);
      advance(const Duration(seconds: 11));
      expect(cache.get(_vin1), isNull);
    });
  });
}
