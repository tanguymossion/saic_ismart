/// Models for the SAIC iSmart vehicle remote-control API.
///
/// Source: `api/vehicle/schema.py:VehicleControlReq/Resp`, section 7 of
/// TECHNICAL_REFERENCE.md.
library;

import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'vehicle_status.dart' show BasicVehicleStatus, GpsPosition;

// ── RvcReqType ────────────────────────────────────────────────────────────────

/// Remote vehicle command type codes sent in `rvcReqType`.
///
/// Source: `api/vehicle/schema.py:RvcReqType`
enum RvcReqType {
  /// Activate the find-my-car feature (horn + lights).
  findMyCar('0'),

  /// Lock all doors.
  closeLocks('1'),

  /// Unlock all doors.
  openLocks('2'),

  /// Control windows and sunroof.
  windows('3'),

  /// Key management command.
  keyManagement('4'),

  /// Heated seat control.
  heatedSeats('5'),

  /// Climate (A/C / heat) control.
  climate('6'),

  /// Air ioniser / clean-air mode.
  airClean('7'),

  /// Remote engine start/stop.
  engineControl('17'),

  /// Force a status refresh from the vehicle.
  remoteRefresh('18'),

  /// Remote immobiliser control.
  remoteImmobilizer('19'),

  /// Rear-window heater control.
  remoteHeatRearWindow('32'),

  /// Sentinel maximum value — not a real command type.
  maxValue('597');

  /// Raw string value sent in `rvcReqType`.
  final String value;

  // ignore: public_member_api_docs
  const RvcReqType(this.value);
}

// ── VehicleLockId ─────────────────────────────────────────────────────────────

/// Lock target for [RvcReqType.openLocks] commands.
///
/// Sent as `paramId 7` (`RvcParamsId.lockId`) in the `rvcParams` list.
/// Source: `api/vehicle/locks/__init__.py:VehicleLockId`
enum VehicleLockId {
  /// All passenger doors (raw value 3).
  doors(3),

  /// Tailgate / boot (raw value 2).
  tailgate(2);

  /// Raw byte value sent as the Base64-encoded `paramValue`.
  final int raw;

  // ignore: public_member_api_docs
  const VehicleLockId(this.raw);
}

// ── RvcParamsId ───────────────────────────────────────────────────────────────

/// Parameter IDs used in `rvcParams` entries.
///
/// Source: `api/vehicle/schema.py:RvcParamsId`
enum RvcParamsId {
  /// Enable flag for find-my-car (1 = enable).
  findMyCarEnable(1),

  /// Horn activation for find-my-car.
  findMyCarHorn(2),

  /// Lights activation for find-my-car.
  findMyCarLights(3),

  /// Unknown parameter 4.
  unk4(4),

  /// Unknown parameter 5.
  unk5(5),

  /// Unknown parameter 6.
  unk6(6),

  /// Lock command identifier (1 = lock, 2 = unlock).
  lockId(7),

  /// Sunroof control.
  windowSunroof(8),

  /// Driver window control.
  windowDriver(9),

  /// Second window control.
  window2(10),

  /// Third window control.
  window3(11),

  /// Fourth window control.
  window4(12),

  /// Open/close flag for window commands (0 = close, 1 = open).
  windowOpenClose(13),

  /// Driver heated seat level.
  heatedSeatDriver(17),

  /// Passenger heated seat level.
  heatedSeatPassenger(18),

  /// Climate fan speed / mode — see [ClimateMode].
  fanSpeed(19),

  /// Climate temperature index (0–8 maps to approximately 16–28 °C).
  temperature(20),

  /// A/C on/off flag (0 = off, 1 = on).
  acOnOff(22),

  /// Rear-window heater control.
  remoteHeatRearWindow(23),

  /// Sentinel maximum parameter ID — not a real parameter.
  paramsMax(255);

  /// Raw integer value sent in `paramId`.
  final int value;

  // ignore: public_member_api_docs
  const RvcParamsId(this.value);
}

// ── ClimateMode ───────────────────────────────────────────────────────────────

/// Fan speed mode for [SaicClient.startClimate].
///
/// Source: `RvcParamsId.FAN_SPEED` values in TECHNICAL_REFERENCE.md §7.
enum ClimateMode {
  /// Climate off.
  off(0),

  /// Blow mode — fan only, no heating or cooling.
  blow(1),

  /// Normal A/C or heating mode.
  normal(2),

  /// Defrost mode — maximum fan with windscreen heating.
  defrost(5);

  /// Raw integer value sent as the `fanSpeed` parameter.
  final int raw;

  // ignore: public_member_api_docs
  const ClimateMode(this.raw);
}

// ── RvcParam ──────────────────────────────────────────────────────────────────

/// A single parameter in the `rvcParams` list.
class RvcParam {
  /// Parameter identifier — see [RvcParamsId] for known values.
  final int paramId;

  /// Parameter value encoded as a Base64 string (typically a single byte).
  final String paramValue;

  // ignore: public_member_api_docs
  const RvcParam({required this.paramId, required this.paramValue});

  Map<String, dynamic> toJson() => {
        'paramId': paramId,
        'paramValue': paramValue,
      };
}

// ── VehicleControlResponse ────────────────────────────────────────────────────

/// Response from `POST /vehicle/control`.
///
/// [rvcReqSts] is decoded from either a Base64 string or a raw integer per
/// quirk #8 in TECHNICAL_REFERENCE.md. `null` when the field is absent.
///
/// Source: `api/vehicle/schema.py:VehicleControlResp`
class VehicleControlResponse {
  /// Vehicle status snapshot included in the control response, if present.
  final BasicVehicleStatus? basicVehicleStatus;

  /// GPS position snapshot included in the control response, if present.
  final GpsPosition? gpsPosition;

  /// Failure type code when the command was rejected; `null` on success.
  final int? failureType;

  /// Decoded request status bytes; `null` when absent or zero-length int.
  final Uint8List? rvcReqSts;

  const VehicleControlResponse({
    this.basicVehicleStatus,
    this.gpsPosition,
    this.failureType,
    this.rvcReqSts,
  });

  factory VehicleControlResponse.fromJson(Map<String, dynamic> json) {
    final basicRaw = json['basicVehicleStatus'];
    final gpsRaw = json['gpsPosition'];

    return VehicleControlResponse(
      basicVehicleStatus: basicRaw == null
          ? null
          : BasicVehicleStatus.fromJson(basicRaw as Map<String, dynamic>),
      gpsPosition: gpsRaw == null
          ? null
          : GpsPosition.fromJson(gpsRaw as Map<String, dynamic>),
      failureType: json['failureType'] as int?,
      rvcReqSts: _decodeBytes(json['rvcReqSts']),
    );
  }

  // Quirk #8: rvcReqSts can be a Base64 string or a raw int.
  static Uint8List? _decodeBytes(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return base64Decode(raw);
    if (raw is int) {
      if (raw == 0) return Uint8List(0);
      final byteCount = (raw.bitLength + 7) ~/ 8;
      final result = Uint8List(byteCount);
      var remaining = raw;
      for (var i = byteCount - 1; i >= 0; i--) {
        result[i] = remaining & 0xff;
        remaining >>= 8;
      }
      return result;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VehicleControlResponse &&
          basicVehicleStatus == other.basicVehicleStatus &&
          gpsPosition == other.gpsPosition &&
          failureType == other.failureType &&
          _uint8ListEqual(rvcReqSts, other.rvcReqSts);

  @override
  int get hashCode =>
      Object.hash(basicVehicleStatus, gpsPosition, failureType, rvcReqSts);
}

bool _uint8ListEqual(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
