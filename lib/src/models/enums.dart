/// Typed enums for integer status fields in [BasicVehicleStatus].
///
/// Each enum exposes the [raw] int value from the API and a [fromRaw] factory
/// that returns `null` for `null` input or any unrecognised raw value.
library;

/// Typed state of a vehicle door.
enum DoorStatus {
  /// Door is closed.
  closed(0),

  /// Door is open.
  open(1);

  /// Raw API integer value.
  final int raw;

  // ignore: public_member_api_docs
  const DoorStatus(this.raw);

  /// Returns the [DoorStatus] for [raw], or `null` for `null` or unrecognised values.
  static DoorStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}

/// Typed state of a vehicle window.
enum WindowStatus {
  /// Window is closed.
  closed(0),

  /// Window is open.
  open(1);

  /// Raw API integer value.
  final int raw;

  // ignore: public_member_api_docs
  const WindowStatus(this.raw);

  /// Returns the [WindowStatus] for [raw], or `null` for `null` or unrecognised values.
  ///
  /// Note: raw value `1000` has been observed on MG3 hardware but its meaning
  /// is unknown — it is treated as unrecognised and returns `null`.
  static WindowStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}

/// Typed lock state of the vehicle.
enum LockStatus {
  /// Vehicle is unlocked.
  unlocked(0),

  /// Vehicle is locked.
  locked(1);

  /// Raw API integer value.
  final int raw;

  // ignore: public_member_api_docs
  const LockStatus(this.raw);

  /// Returns the [LockStatus] for [raw], or `null` for `null` or unrecognised values.
  static LockStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}

/// Typed state of the vehicle bonnet (front hood).
enum BonnetStatus {
  /// Bonnet is closed.
  closed(0),

  /// Bonnet is open.
  open(1);

  /// Raw API integer value.
  final int raw;

  // ignore: public_member_api_docs
  const BonnetStatus(this.raw);

  /// Returns the [BonnetStatus] for [raw], or `null` for `null` or unrecognised values.
  static BonnetStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}

/// Typed state of the vehicle boot (rear trunk/tailgate).
enum BootStatus {
  /// Boot is closed.
  closed(0),

  /// Boot is open.
  open(1);

  /// Raw API integer value.
  final int raw;

  // ignore: public_member_api_docs
  const BootStatus(this.raw);

  /// Returns the [BootStatus] for [raw], or `null` for `null` or unrecognised values.
  static BootStatus? fromRaw(int? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return null;
  }
}
