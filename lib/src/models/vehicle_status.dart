/// Real-time vehicle telemetry models for the SAIC iSmart API.
///
/// The top-level response from `GET /vehicle/status` is [VehicleStatus].
/// All fields throughout this file are nullable — the API omits fields that
/// do not apply to a vehicle's powertrain (see BEV/PHEV/ICE matrix in
/// TECHNICAL_REFERENCE.md §5).
///
/// Source: `api/vehicle/schema.py`, `api/schema.py`
library;

import '../utils/unit_utils.dart' as unit_utils;
import 'enums.dart';

// ── GpsStatus ─────────────────────────────────────────────────────────────────

/// GPS signal quality levels returned in [GpsPosition.gpsStatus].
///
/// Source: `api/schema.py:GpsStatus`
enum GpsStatus {
  /// No GPS signal.
  noSignal(0),

  /// Time synchronised but no position fix.
  timeFix(1),

  /// 2-D position fix (latitude/longitude only).
  fix2d(2),

  /// Full 3-D position fix (latitude/longitude/altitude).
  fix3d(3);

  // ignore: public_member_api_docs
  const GpsStatus(this.value);

  /// Raw integer value as returned by the API.
  final int value;

  /// Returns the [GpsStatus] for [value], falling back to [noSignal] for
  /// any undocumented value.
  static GpsStatus fromValue(int value) => GpsStatus.values.firstWhere(
        (e) => e.value == value,
        orElse: () => GpsStatus.noSignal,
      );
}

// ── GPS sub-models ────────────────────────────────────────────────────────────

/// WGS84 position in raw integer format.
///
/// Divide [latitude] and [longitude] by 1,000,000 to obtain decimal degrees.
/// Source: `api/schema.py:GpsPosition.wayPoint.position`
class Position {
  /// Raw latitude integer — divide by 1,000,000 for decimal degrees.
  final int? latitude;

  /// Raw longitude integer — divide by 1,000,000 for decimal degrees.
  final int? longitude;

  /// Raw altitude value (unit undocumented).
  final int? altitude;

  // ignore: public_member_api_docs
  const Position({this.latitude, this.longitude, this.altitude});

  /// Parses a [Position] from the `position` sub-object in the GPS JSON.
  factory Position.fromJson(Map<String, dynamic> json) => Position(
        latitude: json['latitude'] as int?,
        longitude: json['longitude'] as int?,
        altitude: json['altitude'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          altitude == other.altitude;

  @override
  int get hashCode => Object.hash(latitude, longitude, altitude);
}

/// A GPS waypoint containing position, heading, speed, and fix quality.
///
/// Source: `api/schema.py:GpsPosition.wayPoint`
class WayPoint {
  /// Raw position in integer degrees × 1,000,000.
  final Position? position;

  /// Horizontal dilution of precision.
  final int? hdop;

  /// Heading in degrees (0–359).
  final int? heading;

  /// Number of satellites used for this fix.
  final int? satellites;

  /// Speed (unit undocumented).
  final int? speed;

  // ignore: public_member_api_docs
  const WayPoint({
    this.position,
    this.hdop,
    this.heading,
    this.satellites,
    this.speed,
  });

  /// Parses a [WayPoint] from the `wayPoint` sub-object in the GPS JSON.
  factory WayPoint.fromJson(Map<String, dynamic> json) => WayPoint(
        position: json['position'] == null
            ? null
            : Position.fromJson(json['position'] as Map<String, dynamic>),
        hdop: json['hdop'] as int?,
        heading: json['heading'] as int?,
        satellites: json['satellites'] as int?,
        speed: json['speed'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WayPoint &&
          position == other.position &&
          hdop == other.hdop &&
          heading == other.heading &&
          satellites == other.satellites &&
          speed == other.speed;

  @override
  int get hashCode =>
      Object.hash(position, hdop, heading, satellites, speed);
}

/// Vehicle GPS location and fix quality.
///
/// Use [latitudeDegrees] and [longitudeDegrees] instead of the raw integer
/// fields in [WayPoint.position].
///
/// Source: `api/schema.py:GpsPosition`
class GpsPosition {
  /// Signal quality. Maps to [GpsStatus] enum.
  final GpsStatus? gpsStatus;

  /// Unix timestamp (seconds) of the GPS fix.
  final int? timeStamp;

  /// Waypoint data — position, heading, speed, satellites.
  final WayPoint? wayPoint;

  // ignore: public_member_api_docs
  const GpsPosition({this.gpsStatus, this.timeStamp, this.wayPoint});

  /// Latitude in decimal degrees, derived from the raw integer field
  /// (`wayPoint.position.latitude / 1,000,000`). `null` if unavailable.
  double? get latitudeDegrees {
    final raw = wayPoint?.position?.latitude;
    return raw == null ? null : raw / 1000000.0;
  }

  /// Longitude in decimal degrees, derived from the raw integer field
  /// (`wayPoint.position.longitude / 1,000,000`). `null` if unavailable.
  double? get longitudeDegrees {
    final raw = wayPoint?.position?.longitude;
    return raw == null ? null : raw / 1000000.0;
  }

  /// Parses a [GpsPosition] from the `gpsPosition` JSON object.
  factory GpsPosition.fromJson(Map<String, dynamic> json) => GpsPosition(
        gpsStatus: json['gpsStatus'] == null
            ? null
            : GpsStatus.fromValue(json['gpsStatus'] as int),
        timeStamp: json['timeStamp'] as int?,
        wayPoint: json['wayPoint'] == null
            ? null
            : WayPoint.fromJson(json['wayPoint'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsPosition &&
          gpsStatus == other.gpsStatus &&
          timeStamp == other.timeStamp &&
          wayPoint == other.wayPoint;

  @override
  int get hashCode => Object.hash(gpsStatus, timeStamp, wayPoint);
}

// ── BasicVehicleStatus ────────────────────────────────────────────────────────

/// Core vehicle telemetry snapshot.
///
/// All fields are `int?`. The API omits fields that do not apply to the
/// vehicle's powertrain:
/// - BEV: `fuelRange`/`fuelLevelPrc` are null; `fuelRangeElec`/`vehElecRngDsp`
///   are present.
/// - ICE: electric range fields are null; fuel fields are present.
/// - PHEV: both sets of fields may be present.
///
/// Source: `api/vehicle/schema.py:BasicVehicleStatus`
class BasicVehicleStatus {
  /// 12 V battery voltage (raw, unit undocumented).
  final int? batteryVoltage;

  /// Hood/bonnet state (0 = closed, assumed).
  final int? bonnetStatus;

  /// Trunk/boot state (0 = closed, assumed).
  final int? bootStatus;

  /// CAN bus activity status.
  final int? canBusActive;

  /// Cluster-displayed fuel level segment.
  final int? clstrDspdFuelLvlSgmt;

  /// Current journey identifier.
  final int? currentJourneyId;

  /// Distance of the current journey (raw, unit undocumented).
  final int? currentJourneyDistance;

  /// Low-beam headlight state.
  final int? dippedBeamStatus;

  /// Driver door state (0 = closed, assumed).
  final int? driverDoor;

  /// Driver window state.
  final int? driverWindow;

  /// Engine status. `1` = running — used in [isEngineRunning].
  final int? engineStatus;

  /// Undocumented extended field 1.
  final int? extendedData1;

  /// Undocumented extended field 2.
  final int? extendedData2;

  /// Exterior temperature (raw, offset/scale undocumented).
  final int? exteriorTemperature;

  /// Front-left seat heat level (0–3, assumed).
  final int? frontLeftSeatHeatLevel;

  /// Front-left tyre pressure (raw, unit undocumented).
  final int? frontLeftTyrePressure;

  /// Front-right seat heat level.
  final int? frontRightSeatHeatLevel;

  /// Front-right tyre pressure (raw).
  final int? frontRightTyrePressure;

  /// Fuel level percentage (0–100). Null for BEV.
  final int? fuelLevelPrc;

  /// ICE range (raw, unit undocumented — likely metres or 0.1 km). Null for BEV.
  final int? fuelRange;

  /// Electric range (raw). Null for ICE.
  final int? fuelRangeElec;

  /// Handbrake state. `1` = applied — used in [isParked].
  final int? handBrake;

  /// Interior temperature (raw, offset/scale undocumented).
  final int? interiorTemperature;

  /// Last key-fob detection event (raw).
  final int? lastKeySeen;

  /// Door lock state.
  final int? lockStatus;

  /// High-beam headlight state.
  final int? mainBeamStatus;

  /// Total odometer reading (raw, unit undocumented — likely metres or 0.1 km).
  final int? mileage;

  /// Passenger door state.
  final int? passengerDoor;

  /// Passenger window state.
  final int? passengerWindow;

  /// Vehicle power mode.
  final int? powerMode;

  /// Rear-left door state.
  final int? rearLeftDoor;

  /// Rear-left tyre pressure (raw).
  final int? rearLeftTyrePressure;

  /// Rear-left window state.
  final int? rearLeftWindow;

  /// Rear-right door state.
  final int? rearRightDoor;

  /// Rear-right tyre pressure (raw).
  final int? rearRightTyrePressure;

  /// Rear-right window state.
  final int? rearRightWindow;

  /// Remote climate control state.
  final int? remoteClimateStatus;

  /// Remote heated rear window state.
  final int? rmtHtdRrWndSt;

  /// Side/position lights state.
  final int? sideLightStatus;

  /// Steering wheel heat level.
  final int? steeringHeatLevel;

  /// Steering wheel heat failure reason code.
  final int? steeringWheelHeatFailureReason;

  /// Sunroof state.
  final int? sunroofStatus;

  /// Unix timestamp of the last CAN bus message.
  final int? timeOfLastCANBUSActivity;

  /// Displayed electric range. Null for ICE.
  final int? vehElecRngDsp;

  /// Vehicle alarm state.
  final int? vehicleAlarmStatus;

  /// Tyre pressure monitoring system (TPMS) status.
  final int? wheelTyreMonitorStatus;

  // ignore: public_member_api_docs
  const BasicVehicleStatus({
    this.batteryVoltage,
    this.bonnetStatus,
    this.bootStatus,
    this.canBusActive,
    this.clstrDspdFuelLvlSgmt,
    this.currentJourneyId,
    this.currentJourneyDistance,
    this.dippedBeamStatus,
    this.driverDoor,
    this.driverWindow,
    this.engineStatus,
    this.extendedData1,
    this.extendedData2,
    this.exteriorTemperature,
    this.frontLeftSeatHeatLevel,
    this.frontLeftTyrePressure,
    this.frontRightSeatHeatLevel,
    this.frontRightTyrePressure,
    this.fuelLevelPrc,
    this.fuelRange,
    this.fuelRangeElec,
    this.handBrake,
    this.interiorTemperature,
    this.lastKeySeen,
    this.lockStatus,
    this.mainBeamStatus,
    this.mileage,
    this.passengerDoor,
    this.passengerWindow,
    this.powerMode,
    this.rearLeftDoor,
    this.rearLeftTyrePressure,
    this.rearLeftWindow,
    this.rearRightDoor,
    this.rearRightTyrePressure,
    this.rearRightWindow,
    this.remoteClimateStatus,
    this.rmtHtdRrWndSt,
    this.sideLightStatus,
    this.steeringHeatLevel,
    this.steeringWheelHeatFailureReason,
    this.sunroofStatus,
    this.timeOfLastCANBUSActivity,
    this.vehElecRngDsp,
    this.vehicleAlarmStatus,
    this.wheelTyreMonitorStatus,
  });

  /// `true` when the vehicle is parked — engine not running OR handbrake on.
  ///
  /// Formula: `engineStatus != 1 || handBrake == 1`
  /// Source: `api/vehicle/schema.py:BasicVehicleStatus.is_parked`
  bool get isParked => engineStatus != 1 || handBrake == 1;

  /// `true` when `engineStatus == 1`.
  ///
  /// Source: `api/vehicle/schema.py:BasicVehicleStatus.is_engine_running`
  bool get isEngineRunning => engineStatus == 1;

  /// Mileage in kilometres (`null` when [mileage] is `null`).
  double? get mileageKm => mileage == null ? null : unit_utils.mileageToKm(mileage!);

  /// Mileage in miles (`null` when [mileage] is `null`).
  double? get mileageMiles =>
      mileage == null ? null : unit_utils.mileageToMiles(mileage!);

  /// Fuel range in kilometres (`null` when [fuelRange] is `null`).
  double? get fuelRangeKm =>
      fuelRange == null ? null : unit_utils.fuelRangeToKm(fuelRange!);

  /// Exterior temperature in °C; `null` when not available (-128 sentinel).
  int? get exteriorTemperatureCelsius => exteriorTemperature == null
      ? null
      : unit_utils.temperatureCelsius(exteriorTemperature!);

  /// Interior temperature in °C; `null` when not available (-128 sentinel).
  int? get interiorTemperatureCelsius => interiorTemperature == null
      ? null
      : unit_utils.temperatureCelsius(interiorTemperature!);

  /// Battery voltage raw value; `null` when not available (-128 sentinel).
  int? get batteryVoltageValue => batteryVoltage == null
      ? null
      : unit_utils.batteryVoltageSensor(batteryVoltage!);

  /// Front-left tyre pressure in bar (`null` when unavailable).
  double? get frontLeftTyrePressureBar =>
      frontLeftTyrePressure == null
          ? null
          : unit_utils.tyrePressureToBar(frontLeftTyrePressure!);

  /// Front-right tyre pressure in bar (`null` when unavailable).
  double? get frontRightTyrePressureBar =>
      frontRightTyrePressure == null
          ? null
          : unit_utils.tyrePressureToBar(frontRightTyrePressure!);

  /// Rear-left tyre pressure in bar (`null` when unavailable).
  double? get rearLeftTyrePressureBar =>
      rearLeftTyrePressure == null
          ? null
          : unit_utils.tyrePressureToBar(rearLeftTyrePressure!);

  /// Rear-right tyre pressure in bar (`null` when unavailable).
  double? get rearRightTyrePressureBar =>
      rearRightTyrePressure == null
          ? null
          : unit_utils.tyrePressureToBar(rearRightTyrePressure!);

  DoorStatus? get driverDoorStatus => DoorStatus.fromRaw(driverDoor);
  DoorStatus? get passengerDoorStatus => DoorStatus.fromRaw(passengerDoor);
  DoorStatus? get rearLeftDoorStatus => DoorStatus.fromRaw(rearLeftDoor);
  DoorStatus? get rearRightDoorStatus => DoorStatus.fromRaw(rearRightDoor);
  WindowStatus? get driverWindowStatus => WindowStatus.fromRaw(driverWindow);
  WindowStatus? get passengerWindowStatus =>
      WindowStatus.fromRaw(passengerWindow);
  WindowStatus? get rearLeftWindowStatus => WindowStatus.fromRaw(rearLeftWindow);
  WindowStatus? get rearRightWindowStatus =>
      WindowStatus.fromRaw(rearRightWindow);
  LockStatus? get lockState => LockStatus.fromRaw(lockStatus);
  BonnetStatus? get bonnetState => BonnetStatus.fromRaw(bonnetStatus);
  BootStatus? get bootState => BootStatus.fromRaw(bootStatus);

  /// Parses a [BasicVehicleStatus] from the `basicVehicleStatus` JSON object.
  factory BasicVehicleStatus.fromJson(Map<String, dynamic> json) =>
      BasicVehicleStatus(
        batteryVoltage: json['batteryVoltage'] as int?,
        bonnetStatus: json['bonnetStatus'] as int?,
        bootStatus: json['bootStatus'] as int?,
        canBusActive: json['canBusActive'] as int?,
        clstrDspdFuelLvlSgmt: json['clstrDspdFuelLvlSgmt'] as int?,
        currentJourneyId: json['currentJourneyId'] as int?,
        currentJourneyDistance: json['currentJourneyDistance'] as int?,
        dippedBeamStatus: json['dippedBeamStatus'] as int?,
        driverDoor: json['driverDoor'] as int?,
        driverWindow: json['driverWindow'] as int?,
        engineStatus: json['engineStatus'] as int?,
        extendedData1: json['extendedData1'] as int?,
        extendedData2: json['extendedData2'] as int?,
        exteriorTemperature: json['exteriorTemperature'] as int?,
        frontLeftSeatHeatLevel: json['frontLeftSeatHeatLevel'] as int?,
        frontLeftTyrePressure: json['frontLeftTyrePressure'] as int?,
        frontRightSeatHeatLevel: json['frontRightSeatHeatLevel'] as int?,
        frontRightTyrePressure: json['frontRightTyrePressure'] as int?,
        fuelLevelPrc: json['fuelLevelPrc'] as int?,
        fuelRange: json['fuelRange'] as int?,
        fuelRangeElec: json['fuelRangeElec'] as int?,
        handBrake: json['handBrake'] as int?,
        interiorTemperature: json['interiorTemperature'] as int?,
        lastKeySeen: json['lastKeySeen'] as int?,
        lockStatus: json['lockStatus'] as int?,
        mainBeamStatus: json['mainBeamStatus'] as int?,
        mileage: json['mileage'] as int?,
        passengerDoor: json['passengerDoor'] as int?,
        passengerWindow: json['passengerWindow'] as int?,
        powerMode: json['powerMode'] as int?,
        rearLeftDoor: json['rearLeftDoor'] as int?,
        rearLeftTyrePressure: json['rearLeftTyrePressure'] as int?,
        rearLeftWindow: json['rearLeftWindow'] as int?,
        rearRightDoor: json['rearRightDoor'] as int?,
        rearRightTyrePressure: json['rearRightTyrePressure'] as int?,
        rearRightWindow: json['rearRightWindow'] as int?,
        remoteClimateStatus: json['remoteClimateStatus'] as int?,
        rmtHtdRrWndSt: json['rmtHtdRrWndSt'] as int?,
        sideLightStatus: json['sideLightStatus'] as int?,
        steeringHeatLevel: json['steeringHeatLevel'] as int?,
        steeringWheelHeatFailureReason:
            json['steeringWheelHeatFailureReason'] as int?,
        sunroofStatus: json['sunroofStatus'] as int?,
        timeOfLastCANBUSActivity: json['timeOfLastCANBUSActivity'] as int?,
        vehElecRngDsp: json['vehElecRngDsp'] as int?,
        vehicleAlarmStatus: json['vehicleAlarmStatus'] as int?,
        wheelTyreMonitorStatus: json['wheelTyreMonitorStatus'] as int?,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BasicVehicleStatus) return false;
    return batteryVoltage == other.batteryVoltage &&
        bonnetStatus == other.bonnetStatus &&
        bootStatus == other.bootStatus &&
        canBusActive == other.canBusActive &&
        clstrDspdFuelLvlSgmt == other.clstrDspdFuelLvlSgmt &&
        currentJourneyId == other.currentJourneyId &&
        currentJourneyDistance == other.currentJourneyDistance &&
        dippedBeamStatus == other.dippedBeamStatus &&
        driverDoor == other.driverDoor &&
        driverWindow == other.driverWindow &&
        engineStatus == other.engineStatus &&
        extendedData1 == other.extendedData1 &&
        extendedData2 == other.extendedData2 &&
        exteriorTemperature == other.exteriorTemperature &&
        frontLeftSeatHeatLevel == other.frontLeftSeatHeatLevel &&
        frontLeftTyrePressure == other.frontLeftTyrePressure &&
        frontRightSeatHeatLevel == other.frontRightSeatHeatLevel &&
        frontRightTyrePressure == other.frontRightTyrePressure &&
        fuelLevelPrc == other.fuelLevelPrc &&
        fuelRange == other.fuelRange &&
        fuelRangeElec == other.fuelRangeElec &&
        handBrake == other.handBrake &&
        interiorTemperature == other.interiorTemperature &&
        lastKeySeen == other.lastKeySeen &&
        lockStatus == other.lockStatus &&
        mainBeamStatus == other.mainBeamStatus &&
        mileage == other.mileage &&
        passengerDoor == other.passengerDoor &&
        passengerWindow == other.passengerWindow &&
        powerMode == other.powerMode &&
        rearLeftDoor == other.rearLeftDoor &&
        rearLeftTyrePressure == other.rearLeftTyrePressure &&
        rearLeftWindow == other.rearLeftWindow &&
        rearRightDoor == other.rearRightDoor &&
        rearRightTyrePressure == other.rearRightTyrePressure &&
        rearRightWindow == other.rearRightWindow &&
        remoteClimateStatus == other.remoteClimateStatus &&
        rmtHtdRrWndSt == other.rmtHtdRrWndSt &&
        sideLightStatus == other.sideLightStatus &&
        steeringHeatLevel == other.steeringHeatLevel &&
        steeringWheelHeatFailureReason ==
            other.steeringWheelHeatFailureReason &&
        sunroofStatus == other.sunroofStatus &&
        timeOfLastCANBUSActivity == other.timeOfLastCANBUSActivity &&
        vehElecRngDsp == other.vehElecRngDsp &&
        vehicleAlarmStatus == other.vehicleAlarmStatus &&
        wheelTyreMonitorStatus == other.wheelTyreMonitorStatus;
  }

  @override
  int get hashCode => Object.hashAll([
        batteryVoltage,
        bonnetStatus,
        bootStatus,
        canBusActive,
        clstrDspdFuelLvlSgmt,
        currentJourneyId,
        currentJourneyDistance,
        dippedBeamStatus,
        driverDoor,
        driverWindow,
        engineStatus,
        extendedData1,
        extendedData2,
        exteriorTemperature,
        frontLeftSeatHeatLevel,
        frontLeftTyrePressure,
        frontRightSeatHeatLevel,
        frontRightTyrePressure,
        fuelLevelPrc,
        fuelRange,
        fuelRangeElec,
        handBrake,
        interiorTemperature,
        lastKeySeen,
        lockStatus,
        mainBeamStatus,
        mileage,
        passengerDoor,
        passengerWindow,
        powerMode,
        rearLeftDoor,
        rearLeftTyrePressure,
        rearLeftWindow,
        rearRightDoor,
        rearRightTyrePressure,
        rearRightWindow,
        remoteClimateStatus,
        rmtHtdRrWndSt,
        sideLightStatus,
        steeringHeatLevel,
        steeringWheelHeatFailureReason,
        sunroofStatus,
        timeOfLastCANBUSActivity,
        vehElecRngDsp,
        vehicleAlarmStatus,
        wheelTyreMonitorStatus,
      ]);
}

// ── VehicleAlertInfo ──────────────────────────────────────────────────────────

/// Raw vehicle alert. [id] and [value] are 0–255 integers. Meaning of specific
/// id/value pairs is undocumented — no real-world non-empty sample available.
/// Max 64 alerts per response.
///
/// Schema confirmed from ASN.1 v2.1 definition in `saic-java-client`:
/// `VehicleAlertInfo ::= SEQUENCE { id INTEGER(0..255), value INTEGER(0..255) }`
class VehicleAlertInfo {
  final int id;
  final int value;

  const VehicleAlertInfo({required this.id, required this.value});

  factory VehicleAlertInfo.fromJson(Map<String, dynamic> json) =>
      VehicleAlertInfo(
        id: json['id'] as int,
        value: json['value'] as int,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VehicleAlertInfo && id == other.id && value == other.value;

  @override
  int get hashCode => Object.hash(id, value);
}

// ── ExtendedVehicleStatus ─────────────────────────────────────────────────────

/// Extended vehicle status containing alert data.
///
/// Each element of [alertDataSum] is a [VehicleAlertInfo] with an opaque [id]
/// and [value] (both 0–255). The mapping of specific id/value pairs to human-
/// readable meanings is undocumented; no non-empty real-world sample is
/// available. The list holds 0–64 entries per the ASN.1 schema.
///
/// Source: `api/vehicle/schema.py:ExtendedVehicleStatus`,
/// `ASN.1 schema/v2_1/ApplicationData.asn1:RvsExtStatus`
class ExtendedVehicleStatus {
  final List<VehicleAlertInfo> alertDataSum;

  const ExtendedVehicleStatus({this.alertDataSum = const []});

  /// Parses an [ExtendedVehicleStatus] from the `extendedVehicleStatus` JSON object.
  factory ExtendedVehicleStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['alertDataSum'] as List<dynamic>? ?? const [];
    return ExtendedVehicleStatus(
      alertDataSum: raw
          .map((e) => VehicleAlertInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ExtendedVehicleStatus) return false;
    if (alertDataSum.length != other.alertDataSum.length) return false;
    for (var i = 0; i < alertDataSum.length; i++) {
      if (alertDataSum[i] != other.alertDataSum[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(alertDataSum);
}

// ── VehicleStatus (top-level) ─────────────────────────────────────────────────

/// Top-level snapshot returned by `GET /vehicle/status`.
///
/// All sub-objects are nullable — the server may omit any of them.
/// Source: `api/vehicle/schema.py:VehicleStatusResp`
class VehicleStatus {
  /// Core telemetry fields (doors, windows, locks, engine, battery…).
  final BasicVehicleStatus? basicVehicleStatus;

  /// GPS location and fix quality.
  final GpsPosition? gpsPosition;

  /// Alert data (structure undocumented).
  final ExtendedVehicleStatus? extendedVehicleStatus;

  /// Unix timestamp (seconds) of the last status update.
  final int? statusTime;

  // ignore: public_member_api_docs
  const VehicleStatus({
    this.basicVehicleStatus,
    this.gpsPosition,
    this.extendedVehicleStatus,
    this.statusTime,
  });

  /// Parses a [VehicleStatus] from the `data` object in a vehicle-status
  /// API response.
  factory VehicleStatus.fromJson(Map<String, dynamic> json) => VehicleStatus(
        basicVehicleStatus: json['basicVehicleStatus'] == null
            ? null
            : BasicVehicleStatus.fromJson(
                json['basicVehicleStatus'] as Map<String, dynamic>,
              ),
        gpsPosition: json['gpsPosition'] == null
            ? null
            : GpsPosition.fromJson(
                json['gpsPosition'] as Map<String, dynamic>,
              ),
        extendedVehicleStatus: json['extendedVehicleStatus'] == null
            ? null
            : ExtendedVehicleStatus.fromJson(
                json['extendedVehicleStatus'] as Map<String, dynamic>,
              ),
        statusTime: json['statusTime'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VehicleStatus &&
          basicVehicleStatus == other.basicVehicleStatus &&
          gpsPosition == other.gpsPosition &&
          extendedVehicleStatus == other.extendedVehicleStatus &&
          statusTime == other.statusTime;

  @override
  int get hashCode => Object.hash(
        basicVehicleStatus,
        gpsPosition,
        extendedVehicleStatus,
        statusTime,
      );
}
