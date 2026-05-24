# SAIC iSmart API — Technical Reference for Dart Port

Source repository: `SAIC-iSmart-API/saic-python-client-ng` (branch: `master`, v0.9.3)

---

## Table of Contents

1. [Authentication Flow](#1-authentication-flow)
2. [API Endpoints](#2-api-endpoints)
3. [Encryption / Request Signing](#3-encryption--request-signing)
4. [Session & Retry Management](#4-session--retry-management)
5. [Vehicle Status Response Schema](#5-vehicle-status-response-schema)
6. [Charging Status & Control Schema](#6-charging-status--control-schema)
7. [Vehicle Control Commands](#7-vehicle-control-commands)
8. [Known Quirks](#8-known-quirks)

---

## 1. Authentication Flow

### Configuration

Source: `src/saic_ismart_client_ng/model.py`

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `username` | `str` | required | Email or phone number |
| `password` | `str` | required | Plaintext — SHA-1 hashed before sending |
| `username_is_email` | `bool` | `True` | Controls `loginType` field |
| `phone_country_code` | `str\|None` | `None` | Required when not email login |
| `base_uri` | `str` | `https://gateway-mg-eu.soimt.com/api.app/v1/` | EU gateway |
| `tenant_id` | `str` | `"459771"` | EU tenant — hardcoded |
| `region` | `str` | `"eu"` | Set in `REGION` header |
| `sms_delivery_delay` | `float` | `3.0` | Seconds between event-id retries |
| `read_timeout` | `float` | `5.0` | HTTP read timeout in seconds |

### Login Request

Source: `src/saic_ismart_client_ng/api/base.py:login()`

```
POST {base_uri}oauth/token
Content-Type: application/x-www-form-urlencoded
Accept: application/json
Authorization: Basic c3dvcmQ6c3dvcmRfc2VjcmV0
```

The `Authorization` header decodes to `sword:sword_secret` (Base64).

Form body fields:

| Field | Value | Notes |
|---|---|---|
| `grant_type` | `"password"` | Always fixed |
| `username` | `{username}` | As configured |
| `password` | `sha1(plaintext_password)` | SHA-1 hex digest, lowercase |
| `scope` | `"all"` | Always fixed |
| `deviceId` | `"simulator*…*{unix_ts_seconds}###com.saicmotor.europecar"` | The prefix is the literal string `"simulator"` followed by `*` characters to pad the total to a fixed length, then `###com.saicmotor.europecar` |
| `deviceType` | `"0"` | `"2"` for Huawei devices (code comment) |
| `language` | `"EN"` | Always fixed |
| `loginType` | `"2"` (email) or `"1"` (phone) | Conditional — see below |
| `countryCode` | `{phone_country_code}` | Only when `loginType == "1"` |

**Login type selection** (`base.py:login()`):
- If `username_is_email == True`: include `loginType: "2"`
- If `username_is_email == False` and `phone_country_code` is set: include `loginType: "1"` and `countryCode`
- If neither condition matches: raise `SaicApiException`

**Note on the login request and encryption:** The login call uses its own explicit headers and does **not** go through the standard AES encryption pipeline (the `encrypt_httpx_request` hook fires on all requests, but for the OAuth form-body the `application/x-www-form-urlencoded` content-type causes the content to be encrypted as well — see Section 3 for exact rules). The `Authorization: Basic` header is only present on the login call.

### Login Response

Source: `src/saic_ismart_client_ng/api/schema.py:LoginResp`

```json
{
  "code": 0,
  "data": {
    "access_token": "...",
    "token_type": "bearer",
    "expires_in": 3600,
    "refresh_token": "...",
    "scope": "all",
    "jti": "...",
    "user_id": "...",
    "user_name": "...",
    "account": "...",
    "tenant_id": "...",
    "dept_id": "...",
    "post_id": "...",
    "role_id": "...",
    "role_name": "...",
    "client_id": "...",
    "oauth_id": "...",
    "avatar": "...",
    "license": "...",
    "languageType": "...",
    "detail": {
      "languageType": "..."
    }
  },
  "message": "success"
}
```

Fields extracted after login (`base.py:login()`):
- `access_token` — stored as `user_token`, sent as `blade-auth` header on all subsequent requests
- `expires_in` — integer seconds; `token_expiration = now + timedelta(seconds=expires_in)`

**Token refresh:** There is no automatic refresh logic. `is_logged_in` property returns `False` when expired. Callers must call `login()` again. (`base.py:is_logged_in`)

### Token Storage

Source: `src/saic_ismart_client_ng/net/client/__init__.py:SaicApiClient`

- Stored as `self.__user_token` (in-memory string)
- Set via `user_token` setter on `SaicApiClient`
- Transmitted via `blade-auth` header by `encrypt_request()` (`net/crypto.py`)
- On logout: `user_token` set to empty string `""`, `token_expiration` set to `None`

### Error Codes on Login / Auth Failure

Source: `base.py:__deserialize()`

| Return code | HTTP status | Action |
|---|---|---|
| 401 or 403 (in JSON `code`) | any | `logout()` + raise `SaicLogoutException` |
| 401 or 403 (HTTP status) | 401/403 | `logout()` + raise `SaicLogoutException` |
| 2, 3, 7 | any | raise `SaicApiException` (no retry) |

---

## 2. API Endpoints

All paths are relative to `base_uri` (default: `https://gateway-mg-eu.soimt.com/api.app/v1/`).

The URL is constructed as: `f"{base_uri}{path.removeprefix('/')}"` — the path leading slash is stripped, then appended to the base URI directly. (`base.py:__execute_api_call`)

### Standard Headers (applied to every request)

Source: `src/saic_ismart_client_ng/net/crypto.py:encrypt_request()`

| Header | Value | Notes |
|---|---|---|
| `User-Agent` | `Europe/2.1.0 (iPad; iOS 18.5; Scale/2.00)` | Hardcoded |
| `Content-Type` | `{normalized_content_type};charset=utf-8` | See normalization rules |
| `Accept` | `application/json` | Always |
| `Accept-Encoding` | `gzip` | Always |
| `REGION` | `{region}` (e.g. `eu`) | From config |
| `APP-SEND-DATE` | `{unix_timestamp_ms}` | Current time in milliseconds |
| `APP-CONTENT-ENCRYPTED` | `"1"` | Always — indicates body is AES-encrypted |
| `tenant-id` | `{tenant_id}` (e.g. `459771`) | From config |
| `User-Type` | `"app"` | Always |
| `APP-LANGUAGE-TYPE` | `"en"` | Always |
| `blade-auth` | `{access_token}` | Only when `user_token` is non-empty |
| `APP-VERIFICATION-STRING` | `{hmac_sha256_hex}` | See Section 3 |
| `ORIGINAL-CONTENT-TYPE` | `{normalized_content_type}` | Without charset suffix |

### Endpoint Table

| Path | Method | Source File | Uses event-id retry | Body encoding | Description |
|---|---|---|---|---|---|
| `/oauth/token` | POST | `base.py:login()` | No | `application/x-www-form-urlencoded` | Login / token acquisition |
| `/vehicle/list` | GET | `vehicle/__init__.py:vehicle_list()` | No | — | List vehicles linked to account |
| `/vehicle/status` | GET | `vehicle/__init__.py:get_vehicle_status()` | Yes | — | Get vehicle status |
| `/vehicle/control` | POST | `vehicle/__init__.py:send_vehicle_control_command()` | Yes | JSON | Send vehicle RVC command |
| `/vehicle/alarmSwitch` | GET | `vehicle/alarm/__init__.py:get_alarm_switch()` | No | — | Get alarm switch configuration |
| `/vehicle/alarmSwitch` | PUT | `vehicle/alarm/__init__.py:set_alarm_switches()` | No | JSON | Set alarm switches |
| `/vehicle/charging/status` | GET | `vehicle_charging/__init__.py:get_vehicle_charging_status()` | Yes | — | Get charging status |
| `/vehicle/charging/mgmtData` | GET | `vehicle_charging/__init__.py:get_vehicle_charging_management_data()` | Yes | — | Get BMS management data |
| `/vehicle/charging/control` | POST | `vehicle_charging/__init__.py:send_vehicle_charging_control()` | Yes | JSON | Start/stop charging or V2X |
| `/vehicle/charging/reservation` | POST | `vehicle_charging/__init__.py:send_vehicle_charging_reservation()` | Yes | JSON | Set scheduled charging |
| `/vehicle/charging/ptcHeat` | POST | `vehicle_charging/__init__.py:send_vehicle_charging_ptc_heat()` | Yes | JSON | Control battery PTC heating |
| `/vehicle/charging/setting` | POST | `vehicle_charging/__init__.py:send_vehicle_charging_settings()` | Yes | JSON | Set charge current / target SOC |
| `/charging/batteryHeating` | GET | `vehicle_charging/__init__.py:get_vehicle_battery_heating_schedule()` | No | — | Get battery heating schedule |
| `/charging/batteryHeating` | POST | `vehicle_charging/__init__.py:send_vehicle_battery_heating_schedule()` | No | JSON | Set battery heating schedule |
| `/user/timezone` | GET | `user/__init__.py:get_user_timezone()` | No | — | Get user timezone |
| `/message/list` | GET | `message/__init__.py:get_message_list()` | No | — | Get message list (ALARM/COMMAND/NEWS) |
| `/message/status` | PUT | `message/__init__.py:update_message_status()` | No | JSON | Mark message read/deleted |
| `/message/unreadCount` | GET | `message/__init__.py:get_unread_messages_count()` | No | — | Get unread message count |

### VIN Hashing

All endpoints that accept a VIN as a query parameter or in the request body receive a **SHA-256 hex digest** of the raw VIN string, not the VIN itself.

```python
# vehicle/__init__.py
params={"vin": sha256_hex_digest(vin)}
# crypto_utils.py:sha256_hex_digest()
hashlib.sha256().update(content.encode()).hexdigest()
```

### Query Parameters for Key Endpoints

**GET `/vehicle/status`** (`vehicle/__init__.py:get_vehicle_status()`):
```
vin=<sha256(vin)>&vehStatusReqType=2
```
`vehStatusReqType=2` is hardcoded.

**GET `/vehicle/charging/status`** and **GET `/vehicle/charging/mgmtData`**:
```
vin=<sha256(vin)>
```

**GET `/vehicle/alarmSwitch`**:
```
vin=<sha256(vin)>
```

**GET `/charging/batteryHeating`**:
```
vin=<sha256(vin)>
```

**GET `/message/list`**:
```
pageNum=<int>&pageSize=<int>&messageGroup=<ALARM|COMMAND|NEWS>
```

---

## 3. Encryption / Request Signing

This API uses **symmetric AES-128-CBC encryption** for both request and response bodies, plus an **HMAC-SHA-256 signature** in the `APP-VERIFICATION-STRING` header. There is no ASN.1/PER encoding — all payloads are JSON.

Source files: `net/crypto.py`, `crypto_utils.py`, `net/httpx/__init__.py`

### Dependencies

| Python package | Purpose |
|---|---|
| `pycryptodome >= 3.20` | AES-CBC encryption/decryption (`Crypto.Cipher.AES`, `Crypto.Util.Padding`) |
| `httpx >= 0.27` | HTTP client |
| `tenacity >= 9.0` | Retry logic |
| `dacite >= 1.8` | JSON-to-dataclass deserialization |

### Content-Type Normalization

Source: `net/utils.py:normalize_content_type()`

| Original Content-Type | Normalized Value |
|---|---|
| `None` / missing | `application/json` |
| Contains `multipart` | `multipart/form-data` |
| Contains `x-www-form-urlencoded` | `application/x-www-form-urlencoded` |
| Other (e.g. `application/json`) | `application/json` |

The normalized content type is used throughout key and IV derivation. The actual `Content-Type` header sent is `{normalized};charset=utf-8`.

### Request Body Encryption

Source: `net/crypto.py:encrypt_request()`

Encryption is skipped when:
- The body is empty
- The content-type contains `multipart`

**Step 1: Derive encryption key and IV**

```
current_ts = str(int(timestamp_milliseconds))

key_part_1 = md5_hex(request_path + tenant_id + user_token + "app")
key_hex    = md5_hex(key_part_1 + current_ts + "1" + normalized_content_type)
iv_hex     = md5_hex(current_ts)
```

Where `md5_hex(s)` = lowercase MD5 of UTF-8 encoded string, with NO padding (`do_padding=False`).

`request_path` = full URL stripped of `base_uri` prefix, including query string. For example: `/vehicle/status?vin=abc&vehStatusReqType=2`

**Step 2: Encrypt**

```
stripped_body = request_body.strip()
encrypted_hex = AES_CBC_PKCS5(key=unhex(key_hex), iv=unhex(iv_hex), plaintext=stripped_body.encode('utf-8'))
# result is hex-encoded ciphertext
```

The encrypted body replaces the original body in the request (`net/httpx/__init__.py:update_httpx_request_with_content()`).

The `_content` field on the httpx Request is mutated in place (accesses protected member `_content`) — see Section 8.

### Response Body Decryption

Source: `net/crypto.py:decrypt_response()`

Only decrypted when `response.is_success` (2xx status).

**Step 1: Derive key and IV from response headers**

```
app_send_date     = response.headers["APP-SEND-DATE"]
original_ct       = response.headers["ORIGINAL-CONTENT-TYPE"]

key_hex = md5_hex(app_send_date + "1" + original_ct)
iv_hex  = md5_hex(app_send_date)
```

Note: response key derivation does NOT include `request_path`, `tenant_id`, or `user_token`. This is simpler than the request key derivation.

**Step 2: Decrypt**

```
stripped_body = response_body.strip()
plaintext = AES_CBC_PKCS5_decrypt(key=unhex(key_hex), iv=unhex(iv_hex), ciphertext=unhex(stripped_body))
```

### HMAC-SHA-256 Verification String

Source: `net/crypto.py:get_app_verification_string()`

This signature is placed in the `APP-VERIFICATION-STRING` request header.

```
# For requests (NOT responses):
key_part_1  = request_path + tenant_id + user_token + "app"
enc_key_p1  = md5_hex(key_part_1)
enc_key_p2  = current_ts + "1" + content_type
encrypt_key = md5_hex(enc_key_p1 + enc_key_p2)
encrypt_iv  = md5_hex(current_ts)

# Encrypt the request content (same AES step as above):
if len(request_content) > 0:
    encrypt_req = AES_CBC(key=unhex(encrypt_key), iv=unhex(encrypt_iv), plaintext=request_content)
else:
    encrypt_req = ""

# Concatenate the HMAC message:
hmac_message = request_path + tenant_id + user_token + "app" + current_ts + "1" + content_type + encrypt_req

# Derive the HMAC key:
hmac_key = md5_hex(encrypt_key + current_ts)

# Compute:
APP-VERIFICATION-STRING = hmac_sha256(key=hmac_key.encode(), msg=hmac_message.encode()).hexdigest()
```

If `hmac_key` is empty (edge case), the function returns `""`.

### MD5 Hex Digest Implementation Detail

Source: `crypto_utils.py:md5_hex_digest()`

When `do_padding=True`, the string `"00"` is appended before hashing. In all calls within this library, `do_padding=False` is always passed — the padding variant is never used in production paths.

The custom MD5 implementation formats each byte manually:
```python
v1 = v if v >= 0 else v + 0x100
if v1 < 16:
    hex_string += "0"
hex_string += format(v1, "x")
```
This is equivalent to standard `hashlib.md5(...).hexdigest()` with lowercase output.

### Test Vector

Source: `tests/security_test.py`

```
Input:
  request_path    = "/api/v1/data"
  current_ts      = "20230514123000"
  tenant_id       = "1234"
  content_type    = "application/json"
  request_content = '{"key": "value"}'
  user_token      = "dummy_token"

Expected APP-VERIFICATION-STRING:
  "afd4eaf98af2d964f8ea840fc144ee7bae95dbeeeb251d5e3a01371442f92eeb"
```

---

## 4. Session & Retry Management

### Event-ID Retry Pattern

Source: `base.py:__execute_api_call_with_event_id()`, `base.py:__deserialize()`

Certain endpoints require a polling loop. The client sends an initial request with `event-id: 0`. The server may return a response without `data` but with an `event-id` header — this signals "processing, check back later." The client retries with the returned event-id value.

**Retry configuration** (using `tenacity`):
- `stop`: after 30 seconds total
- `wait`: configurable per call; default is `wait_fixed(sms_delivery_delay)` (default: 3.0 seconds)
- Exception for `/vehicle/control`: `wait_chain(wait_fixed(1) + wait_none())` — 1 second for first retry, immediate thereafter

**Retry trigger conditions** (`base.py:__deserialize()`):
1. Response has `event-id` header AND response JSON has no `"data"` key → extract the new event-id from headers, raise `SaicApiRetryException` with that id
2. Response `code != 0` AND request had a non-"0" `event-id` header → raise `SaicApiRetryException` with the same event-id (request the same one again)

**Event-id update logic** (`base.py:saic_api_after_retry()`):
- After each failed attempt, if the exception is `SaicApiRetryException`, the `event_id` kwarg is updated to the new value from the exception before the next retry
- The `event-id` header value starts as `"0"`, gets replaced with whatever the server returns

**Initial request** uses `event-id: 0`. The server returns the actual event-id in its response header when it starts processing asynchronously.

**No retry** conditions:
- `SaicLogoutException` → stop immediately, do not retry
- Generic `SaicApiException` (return codes 2, 3, 7) → stop immediately

### Response Code Handling

Source: `base.py:__deserialize()`

| JSON `code` field | Behavior |
|---|---|
| `0` | Success — deserialize `data` field |
| `2` | Fatal error — raise `SaicApiException` |
| `3` | Fatal error — raise `SaicApiException` |
| `7` | Fatal error — raise `SaicApiException` |
| `401` or `403` | Logout + raise `SaicLogoutException` |
| Other non-zero | If event-id context: retry; else fatal `SaicApiException` |

HTTP status codes `401` and `403` also trigger logout regardless of JSON body.

### No Session Conflict / Single-Session Logic

There is no explicit session conflict detection or "kill previous session" logic in this library. The `SaicApiClient` maintains a single `httpx.AsyncClient` instance per `SaicApiConfiguration`. If you create two `SaicApi` instances with the same credentials, there is no coordination between them.

---

## 5. Vehicle Status Response Schema

### `VehicleStatusResp`

Source: `api/vehicle/schema.py:VehicleStatusResp`

```
GET /vehicle/status?vin={sha256(vin)}&vehStatusReqType=2
```

Response `data` field structure:

| Field | Type | Notes |
|---|---|---|
| `basicVehicleStatus` | `BasicVehicleStatus\|null` | Core status fields |
| `extendedVehicleStatus` | `ExtendedVehicleStatus\|null` | Alert data |
| `gpsPosition` | `GpsPosition\|null` | Location data |
| `statusTime` | `int\|null` | Unix timestamp (seconds) of last status update |

### `BasicVehicleStatus` Fields

Source: `api/vehicle/schema.py:BasicVehicleStatus`

All fields are `int | None`. Unless noted, units/encoding are undocumented in the source.

| Field | Type | Notes / Units |
|---|---|---|
| `batteryVoltage` | `int\|null` | 12V battery voltage (raw, unit unknown) |
| `bonnetStatus` | `int\|null` | Hood/bonnet: 0=closed? |
| `bootStatus` | `int\|null` | Trunk/boot: 0=closed? |
| `canBusActive` | `int\|null` | CAN bus activity status |
| `clstrDspdFuelLvlSgmt` | `int\|null` | Cluster-displayed fuel level segment |
| `currentJourneyId` | `int\|null` | Current journey identifier |
| `currentJourneyDistance` | `int\|null` | Distance of current journey |
| `dippedBeamStatus` | `int\|null` | Low-beam headlights |
| `driverDoor` | `int\|null` | Driver door state |
| `driverWindow` | `int\|null` | Driver window state |
| `engineStatus` | `int\|null` | `1` = engine running (used in `is_engine_running` property) |
| `extendedData1` | `int\|null` | Undocumented |
| `extendedData2` | `int\|null` | Undocumented |
| `exteriorTemperature` | `int\|null` | Exterior temperature (raw, offset/scale unknown) |
| `frontLeftSeatHeatLevel` | `int\|null` | Seat heat level 0-3? |
| `frontLeftTyrePressure` | `int\|null` | Tyre pressure (raw, unit unknown) |
| `frontRightSeatHeatLevel` | `int\|null` | Seat heat level 0-3? |
| `frontRightTyrePressure` | `int\|null` | Tyre pressure (raw) |
| `fuelLevelPrc` | `int\|null` | Fuel level percentage |
| `fuelRange` | `int\|null` | ICE range (raw, likely meters or 0.1km) |
| `fuelRangeElec` | `int\|null` | Electric range (raw) |
| `handBrake` | `int\|null` | `1` = handbrake applied (used in `is_parked`) |
| `interiorTemperature` | `int\|null` | Interior temperature (raw) |
| `lastKeySeen` | `int\|null` | Last key-fob detection (raw) |
| `lockStatus` | `int\|null` | Lock state |
| `mainBeamStatus` | `int\|null` | High-beam headlights |
| `mileage` | `int\|null` | Total odometer (raw, unit unknown — likely meters or 0.1km) |
| `passengerDoor` | `int\|null` | Passenger door state |
| `passengerWindow` | `int\|null` | Passenger window state |
| `powerMode` | `int\|null` | Vehicle power mode |
| `rearLeftDoor` | `int\|null` | Rear-left door state |
| `rearLeftTyrePressure` | `int\|null` | Tyre pressure (raw) |
| `rearLeftWindow` | `int\|null` | Rear-left window state |
| `rearRightDoor` | `int\|null` | Rear-right door state |
| `rearRightTyrePressure` | `int\|null` | Tyre pressure (raw) |
| `rearRightWindow` | `int\|null` | Rear-right window state |
| `remoteClimateStatus` | `int\|null` | Remote climate state |
| `rmtHtdRrWndSt` | `int\|null` | Remote heated rear window state |
| `sideLightStatus` | `int\|null` | Side/position lights |
| `steeringHeatLevel` | `int\|null` | Steering wheel heat level |
| `steeringWheelHeatFailureReason` | `int\|null` | Failure reason code |
| `sunroofStatus` | `int\|null` | Sunroof state |
| `timeOfLastCANBUSActivity` | `int\|null` | Unix timestamp of last CAN bus message |
| `vehElecRngDsp` | `int\|null` | Displayed electric range |
| `vehicleAlarmStatus` | `int\|null` | Alarm state |
| `wheelTyreMonitorStatus` | `int\|null` | TPMS status |

**Computed properties on `BasicVehicleStatus`:**

```python
is_parked       = engineStatus != 1 or handBrake == 1
is_engine_running = engineStatus == 1
```

### `GpsPosition` Fields

Source: `api/schema.py:GpsPosition`

| Field | Type | Notes |
|---|---|---|
| `gpsStatus` | `int\|null` | See `GpsStatus` enum below |
| `timeStamp` | `int\|null` | Unix timestamp of GPS fix |
| `wayPoint.position.latitude` | `int\|null` | Latitude — raw integer, divide by 1,000,000 for degrees (inferred from iSmart protocol) |
| `wayPoint.position.longitude` | `int\|null` | Longitude — raw integer |
| `wayPoint.position.altitude` | `int\|null` | Altitude (raw) |
| `wayPoint.hdop` | `int\|null` | Horizontal dilution of precision |
| `wayPoint.heading` | `int\|null` | Heading in degrees |
| `wayPoint.satellites` | `int\|null` | Number of satellites |
| `wayPoint.speed` | `int\|null` | Speed (raw) |

**`GpsStatus` enum** (`api/schema.py`):

| Value | Name |
|---|---|
| 0 | `NO_SIGNAL` |
| 1 | `TIME_FIX` |
| 2 | `FIX_2D` |
| 3 | `FIX_3D` |

### `ExtendedVehicleStatus`

Source: `api/vehicle/schema.py:ExtendedVehicleStatus`,
confirmed against `ASN.1 schema/v2_1/ApplicationData.asn1:RvsExtStatus` in `saic-java-client`.

`alertDataSum` is a list of 0–64 `VehicleAlertInfo` objects per the ASN.1 schema:

```
RvsExtStatus ::= SEQUENCE {
  vehicleAlerts SEQUENCE SIZE(0..64) OF VehicleAlertInfo
}

VehicleAlertInfo ::= SEQUENCE {
  id    INTEGER(0..255),
  value INTEGER(0..255)
}
```

The schema-conformant wire format is `[{"id": <int>, "value": <int>}, ...]`. The mapping of specific `id`/`value` pairs to human-readable meanings is **undocumented** in every publicly available SAIC client implementation. Neither the Python nor the Java client reads or processes this field after parsing.

**Real-world observation (MG3 Hybrid EU):** the API returns `alertDataSum` as a **flat list of integers** (e.g. `[0, 0, 0, 0, ...]`), not a list of objects. The library handles both formats: integers are stored as `VehicleAlertInfo(id: <int>, value: 0)`. The ASN.1 object form may only appear for non-zero alerts or on other hardware variants.

### BEV vs. PHEV vs. ICE Differences

The API returns a unified response for all vehicle types. Fields that will be null for a given powertrain:

| Field | ICE | PHEV | BEV |
|---|---|---|---|
| `fuelRange` | present | present | null/zero |
| `fuelLevelPrc` | present | present | null/zero |
| `fuelRangeElec` | null/zero | present | present |
| `vehElecRngDsp` | null/zero | present | present |
| Battery/charging fields (section 6) | absent | present | present |

No explicit vehicle-type flag is present in `VehicleStatusResp`. Vehicle type must be inferred from `VinInfo.modelName` or `vehicleModelConfiguration` from the `/vehicle/list` response.

### Real-world observations (MG3 Hybrid EU, 2023)

Confirmed by running against VIN `LSJXXXXXXXXXXXXXXX`.

#### Field units and values

| Field | Observed value | Interpretation |
|---|---|---|
| `mileage` | `243790` | **Decimeters** — divide by 10 for meters, by 10,000 for km (= 24,379 km) |
| `fuelRange` | `3870` | Likely also decimeters (= 387 km range) — same scale as `mileage` |
| `exteriorTemperature` | `-128` | **Sensor not available** sentinel on this model — treat as null |
| `extendedData2` | `-128` | **Not available** sentinel — treat as null |
| `elecRangeStdA`, `elecRangeStdB`, `elecRangeDspMode`, `fuelRangeElec` | `-128` | EV-only fields — `-128` is the null sentinel for fields absent on non-BEV powertrains |
| `tyrePressure` fields | `61`, `65`, `69`, `70` | **PSI × 2** — divide raw by 2 for PSI. Confirmed: FL=69→34.5 PSI/2.38 bar, FR=70→35.0 PSI/2.41 bar, RL=65→32.5 PSI/2.24 bar, RR=61→30.5 PSI/2.10 bar. Consistent with MG3 recommended 2.3 bar / 33 PSI. Sentinel `0` = no sensor; `-128` = not available. |
| `driverWindow` / window fields | `0`, `1000` | `0` = closed (confirmed). `1000` observed — does not map to any known `WindowStatus` value (0=closed, 1=open). Meaning unknown — possibly a bitmask encoding all 4 windows state (e.g. `1000` = front-left open, others closed), or a model-specific flag. `WindowStatus.fromRaw(1000)` returns `null` — treat as unknown until confirmed on other vehicles. |
| `lockStatus` | `1` | **Locked** (confirmed on a physically locked vehicle) |
| `handBrake` | `1` | **Handbrake applied** (confirmed, car was parked) |
| `canBusActive` | `1` | Active |
| `sunroofStatus` | `1` | MG3 has no sunroof — meaning unclear, possibly moonroof/panoramic roof flag |
| `interiorTemperature` | `40` | Plausible °C for a car parked in sun |
| `batteryVoltage` | `125` | Likely **× 0.1 V** = 12.5 V (12 V battery, plausible) |
| `vehicleAlarmStatus` | `2` | Meaning unknown |
| `extendedData1` | `69` | Meaning unknown |

#### GPS

- `latitude` and `longitude` are raw integers — divide by **1,000,000** for decimal degrees.
  Confirmed: `{latitude_raw}` → `{latitude_raw} / 1_000_000 °N`, `{longitude_raw}` → `{longitude_raw} / 1_000_000 °E`.
- `gpsStatus: 2` = `FIX_2D` with 9 satellites confirmed working.

#### event-id polling

- First `/vehicle/status` response: `{"code":0,"message":"success"}` with **no `data` field** and an `event-id` **response header** (e.g. `1222202291`). This is the async trigger — the server has queued the request.
- Second call with the `event-id` header set to that value returns the full `data` object.
- The event-id travels in the **HTTP response header**, not in the JSON body.

---

## 6. Charging Status & Control Schema

### `ChargeStatusResp`

Source: `api/vehicle_charging/schema.py:ChargeStatusResp`

```
GET /vehicle/charging/status?vin={sha256(vin)}
```

| Field | Type | Notes |
|---|---|---|
| `chargingStatus` | `ChargingStatus\|null` | Charging session details |
| `gpsPosition` | `GpsPosition\|null` | Location |
| `statusTime` | `int\|null` | Unix timestamp |

### `ChargingStatus` Fields

Source: `api/vehicle_charging/schema.py:ChargingStatus`

All fields `int | None` unless noted.

| Field | Notes |
|---|---|
| `chargingCurrent` | Charging current (raw) |
| `chargingDuration` | Duration in seconds |
| `chargingElectricityPhase` | AC phase count |
| `chargingGunState` | Gun/plug connection state |
| `chargingPileID` | `str\|null` — charger identifier |
| `chargingPileSupplier` | `str\|null` — charger supplier |
| `chargingState` | Charging state code |
| `chargingTimeLevelPrc` | Time-level percentage |
| `chargingType` | `6` = AC (seen in test data) |
| `chargingVoltage` | Charging voltage (raw) |
| `endTime` | Unix timestamp of charge end |
| `fotaLowestVoltage` | Minimum voltage for FOTA |
| `fuelRangeElec` | Electric range (×0.1 km based on test data showing `3300` → `330km`) |
| `lastChargeEndingPower` | SOC at end of last charge |
| `mileage` | Odometer (see note on `rvsChargeStatus` below) |
| `mileageOfDay` | Mileage today |
| `mileageSinceLastCharge` | Mileage since last charge |
| `powerLevelPrc` | Power level percentage |
| `powerUsageOfDay` | Energy used today |
| `powerUsageSinceLastCharge` | Energy since last charge |
| `realtimePower` | Real-time power (raw) |
| `startTime` | Unix timestamp of charge start |
| `staticEnergyConsumption` | Static energy consumption |
| `totalBatteryCapacity` | Total battery capacity (raw, ×0.1 kWh based on test: `725`→`72.5kWh`) |
| `workingCurrent` | Working current (raw) |
| `workingVoltage` | Working voltage (raw) |

### `ChrgMgmtDataResp`

Source: `api/vehicle_charging/schema.py:ChrgMgmtDataResp`

```
GET /vehicle/charging/mgmtData?vin={sha256(vin)}
```

Contains two sub-objects:
- `chrgMgmtData`: `ChrgMgmtData | None`
- `rvsChargeStatus`: `RvsChargeStatus | None`

### `ChrgMgmtData` — Key Fields with Decoded Values

Source: `api/vehicle_charging/schema.py:ChrgMgmtData`

All raw fields are `int | None`.

| Raw Field | Decoded Property | Formula | Notes |
|---|---|---|---|
| `bmsPackCrnt` | `decoded_current` | `bmsPackCrnt * 0.05 - 1000.0` | Amps (signed; center at 1000) |
| `bmsPackVol` | `decoded_voltage` | `bmsPackVol * 0.25` | Volts |
| (both) | `decoded_power` | `current * voltage / 1000.0` | kW |
| `bmsOnBdChrgTrgtSOCDspCmd` | `charge_target_soc` | `TargetBatteryCode(value)` | Target SOC code |
| `bmsAltngChrgCrntDspCmd` | `charge_current_limit` | `ChargeCurrentLimitCode(value)` | Current limit code |
| `bmsPTCHeatReqDspCmd` | `is_battery_heating` | `== 1` | Bool |
| `ccuEleccLckCtrlDspCmd` | `charging_port_locked` | `== 1` | Bool |
| `bmsChrgSts` | `bms_charging_status` | `BmsChargingStatusCode(value)` | See enum below |
| `bmsChrgSts` | `is_bms_charging` | `value in (1, 3, 10, 12)` | Bool |
| `bmsChrgSpRsn` | `charging_stop_reason` | `ChargingStopReason(value)` | See enum below |
| `bmsPTCHeatResp` | `heating_stop_reason` | `HeatingStopReason(value)` | See enum below |

**Test data reference** (`tests/test_charge_info_resp.py`):
```json
{
  "bmsChrgSts": 1,
  "bmsPackVol": 1649,        // → 412.25V
  "bmsPackCrnt": 19915,      // → 19915*0.05-1000 = -4.25A (discharging)
  "bmsPackSOCDsp": 786,      // likely 78.6%
  "bmsOnBdChrgTrgtSOCDspCmd": 5,  // → TargetBatteryCode.P_90 = 90%
  "bmsAltngChrgCrntDspCmd": 4     // → ChargeCurrentLimitCode.C_MAX
}
```

### `BmsChargingStatusCode` Enum

Source: `api/vehicle_charging/schema.py:BmsChargingStatusCode`

| Value | Name | Note |
|---|---|---|
| 0 | `UNPLUGGED` | |
| 1 | `CHARGING_1` | Possibly AC charging |
| 2 | `CHARGE_DONE` | |
| 3 | `CHARGING_3` | |
| 4 | `CHARGE_FAULT` | |
| 5 | `CONNECTING` | |
| 6 | `CONNECTED_NOT_RECOGNIZED` | |
| 7 | `CONNECTED_NOT_CHARGING` | |
| 8 | `CHARGING_STOPPED` | |
| 9 | `SCHEDULED_CHARGING` | |
| 10 | `CHARGING_10` | Possibly DC fast charging |
| 11 | `SUPER_OFFBOARD_CHARGING` | |
| 12 | `CHARGING_12` | |
| 13 | `V2X_DISCHARGING` | |

### `TargetBatteryCode` Enum

Source: `api/vehicle_charging/schema.py:TargetBatteryCode`

| Code value | Percentage |
|---|---|
| 0 | Ignore (no-op) |
| 1 | 40% |
| 2 | 50% |
| 3 | 60% |
| 4 | 70% |
| 5 | 80% |
| 6 | 90% |
| 7 | 100% |

### `ChargeCurrentLimitCode` Enum

Source: `api/vehicle_charging/schema.py:ChargeCurrentLimitCode`

| Code value | Label |
|---|---|
| 0 | Ignore |
| 1 | 6A |
| 2 | 8A |
| 3 | 16A |
| 4 | Max |

### `ScheduledChargingMode` Enum

Source: `api/vehicle_charging/schema.py:ScheduledChargingMode`

| Value | Name |
|---|---|
| 1 | `UNTIL_CONFIGURED_TIME` |
| 2 | `DISABLED` |
| 3 | `UNTIL_CONFIGURED_SOC` |

### `ChargingStopReason` Enum

| Value | Name |
|---|---|
| 0 | `NO_REASON` |
| 1 | `CHARGER_STATUS_ABNORMAL` |
| 2 | `CHARGER_PORT_OVER_TEMPERATURE` |
| 3 | `CHARGING_GUN_NOT_PROPERLY_PLUGGED_IN` |
| 4 | `CHARGER_VOLTAGE_MISMATCH` |
| 5 | `OTHER_REASON` |
| other | mapped to `OTHER_REASON` |

### `HeatingStopReason` Enum

| Value | Name |
|---|---|
| 0 | `NO_REASON` |
| 1 | `UNKNOWN_1` |
| 2 | `LOW_BATTERY` |
| 3 | `REACHED_STOP_CONDITION` |
| 4 | `UNNECESSARY` |
| 5 | `REACHED_STOP_TIME` |
| 6 | `UNKNOWN_6` |
| 7 | `HEATING_SYSTEM_FAILURE` |

### Scheduled Battery Heating — Time Encoding

Source: `api/vehicle_charging/schema.py:ScheduledBatteryHeatingRequest`

`startTime` is **Unix epoch in milliseconds** (not seconds). When enabling:

```python
# Compute the next occurrence of the desired local time
start_date = now.replace(hour=h, minute=m, second=0, microsecond=0)
if start_date < now:
    start_date += timedelta(days=1)
startTime = int(start_date.timestamp()) * 1000
```

Note the integer truncation: `int(timestamp) * 1000` — the sub-second portion is discarded.

To disable: `startTime=0, status=0`. To enable: `status=1`.

---

## 7. Vehicle Control Commands

### `VehicleControlReq` Structure

Source: `api/vehicle/schema.py:VehicleControlReq`

```json
POST /vehicle/control
{
  "vin": "<sha256(vin)>",
  "rvcReqType": "<string from RvcReqType enum>",
  "rvcParams": [
    { "paramId": <int>, "paramValue": "<base64-encoded bytes>" }
  ]
}
```

`paramValue` is always Base64-encoded bytes (`base64.b64encode(bytes_value).decode("utf-8")`).

### `RvcReqType` Enum (Request Type Codes)

Source: `api/vehicle/schema.py:RvcReqType`

| Name | String Value | Description |
|---|---|---|
| `FIND_MY_CAR` | `"0"` | Flash lights / honk horn |
| `CLOSE_LOCKS` | `"1"` | Lock all doors |
| `OPEN_LOCKS` | `"2"` | Unlock specific lock |
| `WINDOWS` | `"3"` | Window / sunroof control |
| `KEY_MANAGEMENT` | `"4"` | Key management |
| `HEATED_SEATS` | `"5"` | Heated seats |
| `CLIMATE` | `"6"` | Remote climate control |
| `AIR_CLEAN` | `"7"` | Air cleaning |
| `ENGINE_CONTROL` | `"17"` | Engine start/stop |
| `REMOTE_REFRESH` | `"18"` | Remote status refresh |
| `REMOTE_IMMOBILIZER` | `"19"` | Immobilizer |
| `REMOTE_HEAT_REAR_WINDOW` | `"32"` | Rear window heating |
| `MAX_VALUE` | `"597"` | Sentinel value |

### `RvcParamsId` Enum (Parameter IDs)

Source: `api/vehicle/schema.py:RvcParamsId`

| Value | Name | Used in |
|---|---|---|
| 1 | `FIND_MY_CAR_ENABLE` | Find my car |
| 2 | `FIND_MY_CAR_HORN` | Find my car |
| 3 | `FIND_MY_CAR_LIGHTS` | Find my car |
| 4 | `UNK_4` | Unlock (unknown) |
| 5 | `UNK_5` | Unlock (unknown) |
| 6 | `UNK_6` | Unlock (unknown) |
| 7 | `LOCK_ID` | Specifies which lock (DOORS=3, TAILGATE=2) |
| 8 | `WINDOW_SUNROOF` | Window control |
| 9 | `WINDOW_DRIVER` | Window control |
| 10 | `WINDOW_2` | Window control |
| 11 | `WINDOW_3` | Window control |
| 12 | `WINDOW_4` | Window control |
| 13 | `WINDOW_OPEN_CLOSE` | `b"\x03"`=open, `b"\x00"`=close |
| 17 | `HEATED_SEAT_DRIVER` | Level byte |
| 18 | `HEATED_SEAT_PASSENGER` | Level byte |
| 19 | `FAN_SPEED` | Climate: 0=off, 1=blow, 2=normal, 5=defrost |
| 20 | `TEMPERATURE` | Climate: index 0-15 |
| 22 | `AC_ON_OFF` | `b"\x01"`=on, `b"\x00"`=off |
| 23 | `REMOTE_HEAT_REAR_WINDOW` | `b"\x01"`=on, `b"\x00"`=off |
| 255 | `PARAMS_MAX` | Terminator: always `b"\x00\x00\x00\x00"` |

### Control Command Examples

**Lock all doors** (`vehicle/locks/__init__.py:lock_vehicle()`):
```json
{"vin": "<sha256>", "rvcReqType": "1", "rvcParams": null}
```

**Unlock doors** (`vehicle/locks/__init__.py:unlock_vehicle()`):
```json
{
  "vin": "<sha256>",
  "rvcReqType": "2",
  "rvcParams": [
    {"paramId": 4, "paramValue": "AA=="},
    {"paramId": 5, "paramValue": "AA=="},
    {"paramId": 6, "paramValue": "AA=="},
    {"paramId": 7, "paramValue": "Aw=="},
    {"paramId": 255, "paramValue": "AAAAAA=="}
  ]
}
```
(`"Aw=="` = base64(`\x03`) = `VehicleLockId.DOORS.value = 3`)

**Start AC at index 8** (`climate/__init__.py:start_ac()`):
```json
{
  "vin": "<sha256>",
  "rvcReqType": "6",
  "rvcParams": [
    {"paramId": 19, "paramValue": "Ag=="},
    {"paramId": 20, "paramValue": "CA=="},
    {"paramId": 255, "paramValue": "AAAAAA=="}
  ]
}
```

**Find My Car (horn + lights)** (`vehicle/__init__.py:control_find_my_car()`):
```json
{
  "vin": "<sha256>",
  "rvcReqType": "0",
  "rvcParams": [
    {"paramId": 1, "paramValue": "AQ=="},
    {"paramId": 2, "paramValue": "AQ=="},
    {"paramId": 3, "paramValue": "AQ=="},
    {"paramId": 255, "paramValue": "AAAAAA=="}
  ]
}
```

### `VehicleControlResp` Fields

Source: `api/vehicle/schema.py:VehicleControlResp`

| Field | Type | Notes |
|---|---|---|
| `basicVehicleStatus` | `BasicVehicleStatus\|null` | Updated vehicle status |
| `failureType` | `int\|null` | Failure type code |
| `gpsPosition` | `GpsPosition\|null` | Location |
| `rvcReqSts` | `str\|int\|null` | Request status — Base64 or int; use `rvc_req_sts_decoded` for bytes |
| `rvcReqType` | `str\|int\|null` | Echo of request type |

`rvc_req_sts_decoded`: if `str`, decode via `base64.b64decode`; if `int`, convert to bytes via `int.to_bytes`.

---

## 8. Known Quirks

### 1. Hardcoded `Authorization: Basic` for Login

Source: `base.py:login()`

```python
"Authorization": "Basic c3dvcmQ6c3dvcmRfc2VjcmV0"
```
Decodes to `sword:sword_secret`. This is a hardcoded OAuth client credential — never rotated.

### 2. Hardcoded `deviceId` Pattern

Source: `base.py:login()`

```python
firebase_device_id = (
    "simulator*********************************************"
    + str(int(datetime.datetime.now().timestamp()))
)
form_body["deviceId"] = f"{firebase_device_id}###com.saicmotor.europecar"
```
The device ID is synthesized as a static prefix (`simulator` + asterisks) plus the current Unix timestamp. The `###com.saicmotor.europecar` suffix is the bundle ID separator. No real Firebase token is used.

### 3. Hardcoded `User-Agent`

Source: `net/crypto.py:encrypt_request()`

```python
"User-Agent": "Europe/2.1.0 (iPad; iOS 18.5; Scale/2.00)"
```
Impersonates an iPad running iOS 18.5. This must be sent exactly.

### 4. Mutable httpx Internals

Source: `net/httpx/__init__.py:update_httpx_request_with_content()`

```python
modified_request._content = content_as_bytes  # noqa: SLF001
```
The library accesses `httpx.Request._content`, a private/protected attribute. This is acknowledged as a workaround in the source code comment `pylint: disable=protected-access`. A Dart port avoids this by constructing requests with the encrypted body from the start.

### 5. Response Decryption Skipped on Error Responses

Source: `net/httpx/__init__.py:decrypt_httpx_response()`

```python
if resp.is_success:
    # decrypt
```
Error responses (4xx, 5xx) are NOT decrypted. The `__deserialize` method still parses the raw body for error status codes.

### 6. `messageTime` Format Inconsistency

Source: `api/message/schema.py:MessageEntity.message_time`

The API returns `messageTime` in multiple inconsistent date formats. The library tries three formats in order:
1. `"%Y-%m-%d %H:%M:%S"` (e.g. `2024-01-21 17:42:14`)
2. `"%d-%m-%Y %H:%M:%S"` (e.g. `21-01-2024 17:42:14`)
3. `"%d/%m/%Y %H:%M:%S"` (e.g. `21/01/2024 17:42:14`)

If none match, it returns `datetime.now()` and logs an error. A Dart port should implement the same fallback chain.

### 7. `messageId` Can Be int or String

Source: `tests/test_decode_messages.py`

The `messageId` field in message responses is typed `str | int | None` because the API returns it inconsistently — sometimes as a JSON number, sometimes as a JSON string.

### 8. `rvcReqSts` / `rvcReqType` Can Be int or String

Source: `api/vehicle/schema.py:VehicleControlResp`, `api/vehicle_charging/schema.py:ChargingSettingResp`

Multiple response fields that carry binary data come back as either a Base64-encoded string or a raw integer. The `decode_bytes` utility handles both cases:
```python
# serialization_utils.py:decode_bytes()
if isinstance(input_value, str):
    return base64.b64decode(input_value)
if isinstance(input_value, int):
    return input_value.to_bytes((input_value.bit_length() + 7) // 8, "big")
```

### 9. The `APP-CONTENT-ENCRYPTED: 1` Header Is Always Sent

Source: `net/crypto.py:encrypt_request()`

Even when the body is empty or cannot be encrypted (e.g., GET requests with no body), the header `APP-CONTENT-ENCRYPTED: 1` is still set. Only the body encryption step is skipped.

### 10. Request Path Includes Query String for Key Derivation

Source: `net/crypto.py:encrypt_request()`

```python
request_path = str(original_request_url).replace(base_uri, "/")
```
The full URL after stripping the base URI is used — including query parameters. For example, `/vehicle/status?vin=abc123&vehStatusReqType=2`. This path is used in key derivation and in the `APP-VERIFICATION-STRING` computation.

### 11. `vehStatusReqType=2` Is Always Hardcoded

Source: `api/vehicle/__init__.py:get_vehicle_status()`

```python
params={"vin": sha256_hex_digest(vin), "vehStatusReqType": "2"}
```
The `vehStatusReqType` parameter is always `"2"`. The meaning of other values is undocumented.

### 12. `bmsPackSOCDsp` Likely Needs Dividing by 10

From the test data: `bmsPackSOCDsp: 786` — this is likely 78.6% SOC. No explicit scale factor is documented in the source for this field, but the pattern (`786 → 78.6%`) is consistent with a ×0.1 scale.

### 13. No Token Refresh Endpoint

There is no `/oauth/refresh` or token renewal call. When `is_logged_in` returns `False` (token expired), the only option is to call `login()` again with full credentials. The `refresh_token` field in `LoginResp` is present but never used by the library.

### 14. Charging API at `/charging/batteryHeating` vs. `/vehicle/charging/…`

Source: `vehicle_charging/__init__.py`

Two endpoints use `/charging/batteryHeating` (without the `vehicle/` prefix) while all other charging endpoints use `/vehicle/charging/…`. This inconsistency is in the actual API — not a library bug.

### 15. `get_vehicle_charging_settings` Sends a POST with Zeroed Fields

Source: `vehicle_charging/__init__.py:get_vehicle_charging_settings()`

To read settings, the library sends a POST (not GET) to `/vehicle/charging/setting` with all request fields set to `0`. This is a "read" via a POST endpoint.

```python
body = ChargingSettingRequest(
    altngChrgCrntReq=0,
    onBdChrgTrgtSOCReq=0,
    tboxV2XSpSOCReq=0,
    vin=sha256_hex_digest(vin),
)
```
