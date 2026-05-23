/// Typed enums for integer status fields in [BasicVehicleStatus].
///
/// Each enum exposes the [raw] int value from the API and a [fromRaw] factory
/// that returns `null` for `null` input or any unrecognised raw value.
library;

enum DoorStatus {
  closed(0),
  open(1);

  final int raw;
  const DoorStatus(this.raw);

  static DoorStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}

enum WindowStatus {
  closed(0),
  open(1);

  final int raw;
  const WindowStatus(this.raw);

  static WindowStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}

enum LockStatus {
  unlocked(0),
  locked(1);

  final int raw;
  const LockStatus(this.raw);

  static LockStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}

enum BonnetStatus {
  closed(0),
  open(1);

  final int raw;
  const BonnetStatus(this.raw);

  static BonnetStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}

enum BootStatus {
  closed(0),
  open(1);

  final int raw;
  const BootStatus(this.raw);

  static BootStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}
