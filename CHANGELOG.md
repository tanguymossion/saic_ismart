# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] — 2026-05-30

### Documentation
- Remove redundant Features section from README — Roadmap already covers version history
- Complete CHANGELOG v1.0.0 entries — all added models, enums, VehicleFeatures getters and fixes now listed
- Update v1.0.0 release date to 2026-05-30

## [1.0.0] — 2026-05-30

### Added
- `stopFindMyCar(vin)` — silences horn and lights after a Find My Car trigger
- `openTailgate(vin)` — opens the tailgate using `VehicleLockId.tailgate` (`\x02`)
- `startBlowing(vin)` / `startDefrost(vin)` — convenience climate wrappers for fan-only and defrost modes
- `controlHeatedSeats(vin, {driverLevel, passengerLevel})` — sets seat heat level via new `HeatLevel` enum (`off`, `low`, `medium`, `high`)
- `controlRearWindowHeat(vin, {enable})` — turns the rear window heating element on or off
- `controlSunroof(vin, {open})` — opens or closes the sunroof remotely
- `logout()` — clears the current session token and cache; next API call requires a new `login()`
- `isLoggedIn` — returns `true` when a non-expired session is active
- `tokenExpiration` — exposes the current session token's expiry time
- `tokenExpiresIn` — `Duration?` convenience getter for time remaining until token expiry; returns `Duration.zero` if already expired
- `VehicleModelConfigItem` model — exposes raw `vehicleModelConfiguration` items (`itemCode`, `itemName`, `itemValue`) from the vehicle list response
- `Vehicle.vehicleModelConfiguration` — list of `VehicleModelConfigItem` parsed from `GET /vehicle/list`
- `Vehicle.getConfigItem(String itemCode)` — convenience lookup returning the first matching item by code, or `null`
- `Vehicle.series` — exposes the vehicle series string (e.g. `"ZP22 EU"`, `"EH32"`) for powertrain detection
- `VehicleFeatures` — feature detection wrapper on `Vehicle` with 23 getters: `hasSunroof`, `hasRemoteClimate`, `hasRemoteControlledSunroof`, `heatedSeatCapability`, `isElectricVehicle`, `hasElectricVehicleFlag`, `supportsTargetSoc`, `hasTyrePressureMonitoring`, `hasExteriorTemperatureSensor`, `hasInteriorTemperatureSensor`, `hasBatteryVoltageSensor`, `hasKeyPositionSensor`, `hasBonnet`, `hasBoot`, `hasEngine`, `hasBluetoothKey`, `isRightHandDrive`, `isLeftHandDrive`, `doorSensorCount`, `windowSensorCount`, `hasAirbags`, `hasEnergyState`; accessible via `vehicle.features`
- `HeatedSeatCapability` enum — `none`, `onOffOnly`, `multiLevel`
- `VehicleLockId` enum — `doors`, `tailgate`
- `HeatLevel` enum — `off`, `low`, `medium`, `high`

### Fixed
- `code=3` (another command in progress, e.g. climate active) and `code=8` (feature unavailable on this vehicle) now treated as fatal — throws `SaicApiException` immediately without retry
- Retry delay added between vehicle control polling attempts to prevent server hammering on transient errors

## [0.2.0] — 2026-05-24

### Added
- Tyre pressure conversion helpers with confirmed PSI×2 unit (real-world MG3 validation)
- Door, window, lock, bonnet and boot state enums (`DoorStatus`, `WindowStatus`, `LockStatus`, `BonnetStatus`, `BootStatus`)
- Typed `VehicleAlertInfo` model from confirmed ASN.1 schema (`id`, `value` 0–255, max 64 alerts)
- Multi-region support: `australia`, `india`, `turkey`, `restOfWorld` added to `SaicRegion`
- Structured exception hierarchy: `SaicException`, `SaicAuthException`, `SaicSessionConflictException`, `SaicApiException`, `SaicTimeoutException`, `SaicNetworkException`
- Unit conversion helpers: `mileageToKm`, `mileageToMiles`, `fuelRangeToKm`, `temperatureCelsius`, `batteryVoltageRaw`
- Convenience getters on `BasicVehicleStatus`: `mileageKm`, `fuelRangeKm`, `exteriorTemperatureCelsius`, `interiorTemperatureCelsius`, `lockState`, `driverDoorStatus`, `frontLeftTyrePressureBar`, etc.

## [0.1.0] — 2026-05-23

### Added
- Authentication & token refresh (EU region)
- `getVehicles()` — list vehicles linked to account
- `getVehicleStatus(vin)` — GPS, lock state, mileage, full vehicle status
- Built-in cache with configurable TTL + 600s cooldown enforcement
- Single-session conflict detection
- Full AES-128-CBC + HMAC-SHA-256 crypto pipeline
- Tested in production on MG3 Hybrid EU
