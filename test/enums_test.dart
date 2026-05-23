import 'package:saic_ismart/src/models/enums.dart';
import 'package:saic_ismart/src/models/vehicle_status.dart';
import 'package:test/test.dart';

void main() {
  // ── DoorStatus ────────────────────────────────────────────────────────────────

  group('DoorStatus.fromRaw', () {
    test('0 → closed', () => expect(DoorStatus.fromRaw(0), DoorStatus.closed));
    test('1 → open', () => expect(DoorStatus.fromRaw(1), DoorStatus.open));
    test('null → null', () => expect(DoorStatus.fromRaw(null), isNull));
    test('unknown value → null', () => expect(DoorStatus.fromRaw(99), isNull));
  });

  // ── WindowStatus ──────────────────────────────────────────────────────────────

  group('WindowStatus.fromRaw', () {
    test('0 → closed',
        () => expect(WindowStatus.fromRaw(0), WindowStatus.closed));
    test('1 → open', () => expect(WindowStatus.fromRaw(1), WindowStatus.open));
    test('null → null', () => expect(WindowStatus.fromRaw(null), isNull));
    // Real-world: MG3 reports windows as 0 or 1000; 1000 is unknown → null
    test('1000 (MG3 real-world) → null',
        () => expect(WindowStatus.fromRaw(1000), isNull));
    test('unknown value → null',
        () => expect(WindowStatus.fromRaw(99), isNull));
  });

  // ── LockStatus ────────────────────────────────────────────────────────────────

  group('LockStatus.fromRaw', () {
    test('0 → unlocked',
        () => expect(LockStatus.fromRaw(0), LockStatus.unlocked));
    test('1 → locked', () => expect(LockStatus.fromRaw(1), LockStatus.locked));
    test('null → null', () => expect(LockStatus.fromRaw(null), isNull));
    test('unknown value → null', () => expect(LockStatus.fromRaw(99), isNull));
  });

  // ── BonnetStatus ──────────────────────────────────────────────────────────────

  group('BonnetStatus.fromRaw', () {
    test('0 → closed',
        () => expect(BonnetStatus.fromRaw(0), BonnetStatus.closed));
    test('1 → open', () => expect(BonnetStatus.fromRaw(1), BonnetStatus.open));
    test('null → null', () => expect(BonnetStatus.fromRaw(null), isNull));
    test('unknown value → null',
        () => expect(BonnetStatus.fromRaw(99), isNull));
  });

  // ── BootStatus ────────────────────────────────────────────────────────────────

  group('BootStatus.fromRaw', () {
    test('0 → closed', () => expect(BootStatus.fromRaw(0), BootStatus.closed));
    test('1 → open', () => expect(BootStatus.fromRaw(1), BootStatus.open));
    test('null → null', () => expect(BootStatus.fromRaw(null), isNull));
    test('unknown value → null', () => expect(BootStatus.fromRaw(99), isNull));
  });

  // ── BasicVehicleStatus getters ────────────────────────────────────────────────

  group('BasicVehicleStatus enum getters', () {
    BasicVehicleStatus make({
      int? driverDoor,
      int? passengerDoor,
      int? rearLeftDoor,
      int? rearRightDoor,
      int? driverWindow,
      int? passengerWindow,
      int? rearLeftWindow,
      int? rearRightWindow,
      int? lockStatus,
      int? bonnetStatus,
      int? bootStatus,
    }) =>
        BasicVehicleStatus(
          driverDoor: driverDoor,
          passengerDoor: passengerDoor,
          rearLeftDoor: rearLeftDoor,
          rearRightDoor: rearRightDoor,
          driverWindow: driverWindow,
          passengerWindow: passengerWindow,
          rearLeftWindow: rearLeftWindow,
          rearRightWindow: rearRightWindow,
          lockStatus: lockStatus,
          bonnetStatus: bonnetStatus,
          bootStatus: bootStatus,
        );

    test('driverDoorStatus closed when raw=0',
        () => expect(make(driverDoor: 0).driverDoorStatus, DoorStatus.closed));
    test('driverDoorStatus open when raw=1',
        () => expect(make(driverDoor: 1).driverDoorStatus, DoorStatus.open));
    test('driverDoorStatus null when field is null',
        () => expect(make().driverDoorStatus, isNull));

    test('passengerDoorStatus delegates correctly',
        () => expect(make(passengerDoor: 1).passengerDoorStatus, DoorStatus.open));
    test('rearLeftDoorStatus delegates correctly',
        () => expect(make(rearLeftDoor: 0).rearLeftDoorStatus, DoorStatus.closed));
    test('rearRightDoorStatus delegates correctly',
        () => expect(make(rearRightDoor: 1).rearRightDoorStatus, DoorStatus.open));

    test('driverWindowStatus closed when raw=0',
        () => expect(make(driverWindow: 0).driverWindowStatus, WindowStatus.closed));
    test('driverWindowStatus open when raw=1',
        () => expect(make(driverWindow: 1).driverWindowStatus, WindowStatus.open));
    test('driverWindowStatus null when field is null',
        () => expect(make().driverWindowStatus, isNull));
    test('driverWindowStatus null for unknown raw (e.g. 1000)',
        () => expect(make(driverWindow: 1000).driverWindowStatus, isNull));

    test('passengerWindowStatus delegates correctly',
        () => expect(make(passengerWindow: 0).passengerWindowStatus, WindowStatus.closed));
    test('rearLeftWindowStatus delegates correctly',
        () => expect(make(rearLeftWindow: 1).rearLeftWindowStatus, WindowStatus.open));
    test('rearRightWindowStatus delegates correctly',
        () => expect(make(rearRightWindow: 0).rearRightWindowStatus, WindowStatus.closed));

    test('lockState unlocked when raw=0',
        () => expect(make(lockStatus: 0).lockState, LockStatus.unlocked));
    test('lockState locked when raw=1',
        () => expect(make(lockStatus: 1).lockState, LockStatus.locked));
    test('lockState null when field is null',
        () => expect(make().lockState, isNull));

    test('bonnetState closed when raw=0',
        () => expect(make(bonnetStatus: 0).bonnetState, BonnetStatus.closed));
    test('bonnetState open when raw=1',
        () => expect(make(bonnetStatus: 1).bonnetState, BonnetStatus.open));
    test('bonnetState null when field is null',
        () => expect(make().bonnetState, isNull));

    test('bootState closed when raw=0',
        () => expect(make(bootStatus: 0).bootState, BootStatus.closed));
    test('bootState open when raw=1',
        () => expect(make(bootStatus: 1).bootState, BootStatus.open));
    test('bootState null when field is null',
        () => expect(make().bootState, isNull));
  });
}
