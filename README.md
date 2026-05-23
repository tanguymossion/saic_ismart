# saic_ismart

> Dart client for the SAIC iSmart API — MG, Roewe, Maxus/LDV connected vehicles.

[![pub.dev](https://img.shields.io/badge/pub.dev-coming%20soon-grey?style=flat-square)](https://pub.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-pure-0553B1?style=flat-square&logo=dart)](https://dart.dev)

**v0.1 — tested in production on a real MG3 Hybrid EU.**

---

## What is this?

`saic_ismart` is a pure Dart package to interact with the SAIC iSmart connected vehicle API. It works for any vehicle compatible with the MG iSmart app — MG, Roewe, Maxus/LDV models.

It is the **first Dart/Flutter client** in the [SAIC-iSmart-API](https://github.com/SAIC-iSmart-API) open source ecosystem, alongside the existing Python and Java clients.

Pure Dart — no Kotlin, no Swift, no native code. Works in Flutter mobile, Wear OS, desktop, or any Dart project.

---

## Supported vehicles

| Brand | Models | Status |
|---|---|---|
| **MG** | MG3 Hybrid, MG4 EV, MG5 EV, MG ZS EV, MG HS Plug-in… | MG3 Hybrid tested (dev device) |
| **Roewe** | RX5 eMax, ei6 MAX… | Expected — needs contributor |
| **Maxus / LDV** | eT60, eDeliver… | Expected — needs contributor |

EV-specific features (SoC, charging management, climate) require a contributor with the right hardware. See [Contributing](#contributing).

---

## Features (v0.1)

- ✅ Authentication & token refresh
- ✅ List vehicles linked to account
- ✅ `getVehicleStatus(vin)` — GPS location, lock state, mileage
- ✅ Built-in cache with configurable TTL + 600 s cooldown enforcement
- ✅ Single-session conflict detection & handling
- ✅ EU region support (`gateway-mg-eu.soimt.com`)

See the full [roadmap](#roadmap) below.

---

## Quick start

```yaml
# pubspec.yaml
dependencies:
  saic_ismart: ^0.1.0
```

```dart
import 'package:saic_ismart/saic_ismart.dart';

final client = SaicClient(
  username: 'you@example.com',
  password: '••••••••',
  region: SaicRegion.europe,
);

await client.login();

final vehicles = await client.getVehicles();
final status  = await client.getVehicleStatus(vehicles.first.vin);

print(status.isLocked);   // true
print(status.location);   // LatLng(47.99, 0.19)
print(status.mileage);    // 3240 km
```

---

## Real-world output

```
✓ Logged in as user@example.com, token expires at 2026-11-19 15:33:12
✓ Found 1 vehicle(s)
  - MG MG3 2023 (VIN: LSJXXXXXXXXXXXXXXX)
✓ Vehicle status:
  Locked: 1
  Engine running: false
  Parked: true
  Mileage: 243790
  Fuel level: 45%
  Location: 47.XXXXXX, -1.XXXXXX
  GPS status: GpsStatus.fix2d
  Status time: 1779548697
```

---

## Important: API constraints

**Single session** — The SAIC API allows only one active session at a time. Calling this package will pause the official iSmart app for ~900 seconds. The client handles this automatically, but be aware of it if you use the official app alongside.

**600 s cooldown** — The API enforces a minimum delay between vehicle data requests to protect the 12V battery. The client includes a built-in cache that respects this limit. Do not bypass it.

**No real-time data** — Vehicle status is polled, not streamed. Data reflects a snapshot, not a live feed.

---

## Roadmap

### ✅ v0.1 — Foundations
- Auth + token refresh
- `getVehicles()`, `getVehicleStatus(vin)`
- Cache/cooldown + session conflict handling
- EU region
- Tested on MG3 Hybrid EU

### v0.2 — Extended data
- Tyre pressure, window & door state
- Engine status, vehicle alerts
- Multi-region (AU, IN, TR…)
- Structured errors — `SaicException`

### v1.0 — Remote actions + pub.dev release
- Remote lock/unlock
- Find my car
- Horn & lights trigger
- Full docs + example Flutter app
- Published on pub.dev

### v1.x — EV features _(community-driven)_
- Battery SoC (MG4, ZS EV…)
- Charge management — start/stop/schedule
- Remote climate control
- Battery heating

---

## Contributing

**Own an MG4, ZS EV, Roewe or Maxus/LDV?**

EV features can't be developed without the right hardware. If you want to contribute:

1. Open an issue describing your vehicle model and region
2. Check if the iSmart app works for your vehicle
3. Let's build the feature together

This project is based on the reverse engineering work by the [SAIC-iSmart-API](https://github.com/SAIC-iSmart-API) community.

---

## Legal

This package uses the SAIC iSmart API for interoperability purposes, as permitted under the iSmart EULA and EU software directive 2009/24/CE. It is not affiliated with or endorsed by SAIC Motor.

Do not use this package for commercial services that resell SAIC vehicle data without appropriate agreements.

---

## Acknowledgements

Built on top of the reverse engineering work done by the [SAIC-iSmart-API](https://github.com/SAIC-iSmart-API) community — in particular the Python and Java clients which served as reference implementations.
