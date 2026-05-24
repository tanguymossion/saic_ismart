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
  findMyCar('0'),
  closeLocks('1'),
  openLocks('2'),
  windows('3'),
  keyManagement('4'),
  heatedSeats('5'),
  climate('6'),
  airClean('7'),
  engineControl('17'),
  remoteRefresh('18'),
  remoteImmobilizer('19'),
  remoteHeatRearWindow('32'),
  maxValue('597');

  final String value;
  const RvcReqType(this.value);
}

// ── RvcParamsId ───────────────────────────────────────────────────────────────

/// Parameter IDs used in `rvcParams` entries.
///
/// Source: `api/vehicle/schema.py:RvcParamsId`
enum RvcParamsId {
  findMyCarEnable(1),
  findMyCarHorn(2),
  findMyCarLights(3),
  unk4(4),
  unk5(5),
  unk6(6),
  lockId(7),
  windowSunroof(8),
  windowDriver(9),
  window2(10),
  window3(11),
  window4(12),
  windowOpenClose(13),
  heatedSeatDriver(17),
  heatedSeatPassenger(18),
  fanSpeed(19),
  temperature(20),
  acOnOff(22),
  remoteHeatRearWindow(23),
  paramsMax(255);

  final int value;
  const RvcParamsId(this.value);
}

// ── ClimateMode ───────────────────────────────────────────────────────────────

/// Fan speed mode for [SaicClient.startClimate].
///
/// Source: `RvcParamsId.FAN_SPEED` values in TECHNICAL_REFERENCE.md §7.
enum ClimateMode {
  off(0),
  blow(1),
  normal(2),
  defrost(5);

  final int raw;
  const ClimateMode(this.raw);
}

// ── RvcParam ──────────────────────────────────────────────────────────────────

/// A single parameter in the `rvcParams` list.
class RvcParam {
  final int paramId;
  final String paramValue; // Base64-encoded bytes

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
  final BasicVehicleStatus? basicVehicleStatus;
  final GpsPosition? gpsPosition;
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
