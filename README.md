# BiciMAD — Garmin Connect IQ Watch App

A native Garmin smartwatch app for the **BiciMAD** bike-share system in Madrid.  
Find nearby stations, check availability, unlock bikes by plate number, and view your trip history — all from your wrist.

> **Disclaimer:** This is an unofficial third-party app. BiciMAD and EMT Madrid are trademarks of Empresa Municipal de Transportes de Madrid S.A.

---

## Features

| Feature | Description |
|---------|-------------|
| **Stations by GPS** | Find the nearest BiciMAD stations sorted by walking distance |
| **Search by name** | Type a station name and get matching results |
| **Unlock by plate** | Enter a bike's plate number — the app verifies it and physically unlocks the dock |
| **Trip history** | See your last 5 trips and any active trip in progress |
| **Secure login** | Authenticates with your BiciMAD account via the MPass API |
| **Persistent session** | Token stored on-device — no need to login on every use |
| **Bilingual** | Full English and Spanish support (auto-selected by device language) |

---

## Screenshots / Flow

```
Main Menu
├── View Stations
│   ├── Nearby (GPS) ──→ ProgressBar ──→ Station list (native Menu2)
│   │                     "Metro Callao"
│   │                     11/25 · 57m
│   └── Search by Name ──→ TextPicker ──→ ProgressBar ──→ Station list
├── Trips  (logged in only)
│   ├── Active Trip ──→ Bike #, departure station, start time
│   └── History     ──→ Last 5 trips: date, station, cost, duration
├── Unlock Bike
│   ├── Plate  ──→ TextPicker (type plate number)
│   └── Unlock ──→ ProgressBar (verify) → Confirmation → ProgressBar (unlock) → Result
└── Sign In / Sign Out
    ├── Email    ──→ TextPicker (native keyboard via phone)
    ├── Password ──→ TextPicker
    └── Connect  →
```

---

## Architecture

### Watch App (Monkey C / Connect IQ)

Built with Garmin's **Connect IQ SDK 3.2.0+** using native UI components throughout:

| Component | Used for |
|-----------|----------|
| `WatchUi.Menu2` | Main menu, login form, search form, station results, trip history |
| `WatchUi.TextPicker` | Email, password, plate number, station name search |
| `WatchUi.Confirmation` | Unlock confirmation dialog |
| `WatchUi.ProgressBar` | All loading states (GPS, network, unlock) |

### Proxy Backend (Node.js / Cloudflare Workers)

A lightweight proxy server that bridges the watch and the EMT Madrid API.

**Why is a proxy needed?**
1. **Network routing** — Garmin routes all `makeWebRequest()` calls through its own infrastructure, which cannot reach `apiemtpay.emtmadrid.es` directly (returns 404).
2. **Response size** — The EMT stations API returns 632 stations (~296 KB); the Garmin watch buffer is ~32 KB.
3. **DES cryptography** — The bike unlock flow requires a hashcode computed with DES encryption, reverse-engineered from the official APK.

```
Garmin Watch → Garmin Servers → Proxy (Cloudflare/Node.js) → EMT Madrid API
```

---

## API Endpoints

All endpoints are under `/api`. Deploy the proxy to any Node.js host or Cloudflare Workers.

---

### `GET /api/stations`

Returns BiciMAD stations sorted by proximity or filtered by name.  
Reduces the full 296 KB EMT response to <5 KB for the watch.

| Parameter | Type | Description |
|-----------|------|-------------|
| `filter` | `coordinates` \| `name` | Search mode |
| `value` | `lat,lon` or text | GPS coordinates or station name fragment |
| `limit` | number | Max results (default 15, max 30) |

```
GET /api/stations?filter=coordinates&value=40.4168,-3.7038&limit=10
GET /api/stations?filter=name&value=callao
```

**Response:**
```json
[
  { "id": "1406", "name": "2 - Metro Callao", "bikes": 11, "slots": 14, "dist": 57 },
  { "id": "1428", "name": "25A - Plaza de Celenque A", "bikes": 6, "slots": 15, "dist": 179 }
]
```

**Upstream:** `GET https://openapi.emtmadrid.es/v2/transport/bicimad/stations/`  
Uses an anonymous app token — no user account required.

---

### `GET /api/trips`

Returns the user's trip history compacted from ~65 KB to ~7 KB.  
A trip with `active: true` has no `dock` — the user is currently riding.

| Parameter | Type | Description |
|-----------|------|-------------|
| `token` | string | User's `accessToken` |
| `userId` | string | User's ID |

```
GET /api/trips?token=ACCESS_TOKEN&userId=USER_ID
```

**Response:**
```json
{
  "code": "00",
  "data": [
    {
      "id": "41437512",
      "bike": "00015858",
      "mins": 16.2,
      "cost": 0.50,
      "active": false,
      "undock": { "name": "250 - Serrano - CSIC", "ts": "2026-05-29 20:32" },
      "dock":   { "name": "17 - Plaza de Carlos Cambronero", "ts": "2026-05-29 20:48" }
    }
  ]
}
```

**Upstream:** `GET https://apiemtpay.emtmadrid.es/v1/bicimad/trips/`  
Headers: `accessToken`, `userId`, `mode: mPass`

---

### `GET /api/check`

Verifies a bike by plate number and returns its current location.  
Used to show the user bike details before confirming an unlock.

| Parameter | Type | Description |
|-----------|------|-------------|
| `plate` | string | Bike plate number (e.g. `14802`) |
| `token` | string | User's `accessToken` |
| `userId` | string | User's ID |

```
GET /api/check?plate=14802&token=ACCESS_TOKEN&userId=USER_ID
```

**Response:**
```json
{
  "code": "00",
  "data": { "number": "14802", "docker": "802", "fleet": 1, "lat": 40.4239, "lon": -3.7020 }
}
```

`docker` = anchor/dock ID within the station. `fleet`: `1` = BiciMAD Classic, `2` = BiciMAD Go.

**Upstream:** `GET https://apiemtpay.emtmadrid.es/v1/checkresource/bicimad/{plate}/`

---

### `GET /api/unlock`

**Physically unlocks a specific bike** by plate number, starting a trip.  
This is the most complex endpoint — it replicates the full DES encryption flow from the official BiciMAD APK (reverse-engineered via `jadx` + `objdump`).

> **Note:** After a successful unlock (`code: 00`), the dock releases the bike. You have a few minutes to remove the bike before the dock re-locks it automatically.

| Parameter | Type | Description |
|-----------|------|-------------|
| `plate` | string | Bike plate number |
| `token` | string | User's `accessToken` |
| `userId` | string | User's ID |
| `lat` | float | User's latitude |
| `lon` | float | User's longitude |

```
GET /api/unlock?plate=14802&token=ACCESS_TOKEN&userId=USER_ID&lat=40.4239&lon=-3.7020
```

**Response:**
```json
{ "code": "00", "description": "RELEASE OK", "bike": "14802", "docker": "802" }
```

**Full flow (3 steps):**

**1. Verify bike**
```
GET https://apiemtpay.emtmadrid.es/v1/checkresource/bicimad/{plate}/
```
Returns `bikeNumber`, `docker`, GPS coordinates, fleet type.

**2. Compute hashcode** — reverse-engineered from `QRService.cifrarHashcode()` in `EMTingSDK`:
```
plaintext = bikeNumber + "#" + docker + "#" + lon10 + "#" + lat10 + "#U#" + userId
padded    = plaintext padded to multiple of 8 with "#"
step1     = "B" + DES_ECB(padded,  userId.toUpperCase()[0:8])   → HEX UPPERCASE
step1     = step1 padded to multiple of 8 with "Z"
hashcode  = DES_ECB(step1, operatorId.toUpperCase()[0:8])       → BASE64
```
Where `operatorId = "b6cf40a4-6130-439f-9917-15654c79c22e"` (from `Constants.OPERATOR_ID` in APK).  
Keys use `Utils.getEightFirstChars()` = `.toUpperCase().substring(0, 8)`.

**3. Sell ticket**
```
PUT https://apiemtpay.emtmadrid.es/v2/payment/qrcodesdk/sellticket/
Headers: accessToken, hashcode, latitude, longitude, userId, operatorId, ...
```
The server validates the hashcode, signals the PBSC dock system, and releases the bike.

> **Discovery notes:**  
> - Must be `PUT` (method=2 in Volley), not `POST`  
> - Must use `v2` endpoint, not `v1` (`v1` returns `"Not valid xClientId"`)  
> - DES keys must be **UPPERCASE** (`Utils.getEightFirstChars` calls `.toUpperCase()`)  
> - `apiemtpay.emtmadrid.es` is blocked by Garmin's HTTP infrastructure — proxy is required

---

## Authentication

### Anonymous token (stations)

Used by the proxy to fetch station data. No user account needed.

```
GET https://openapi.emtmadrid.es/v2/mobilitylabs/user/login/
Headers: X-ClientId, passKey  (app credentials, no email/password)
```

`X-ClientId` and `passKey` are extracted from the official BiciMAD APK via `libkeys.so` disassembly using `objdump`. They identify the app, not any individual user.

### User token (trips and unlock)

The watch authenticates with the user's BiciMAD account:

```
GET https://openapi.emtmadrid.es/v2/mobilitylabs/user/login/
Headers: X-ClientId, passKey, email, password
```

The `accessToken` is stored in `Application.Storage` and persists across restarts. It expires after 30 days and is checked on every app launch.



## Setup

### Watch App

1. Install the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)

2. **Install [TinyMetrix](https://tinymetrix.com) barrel** — Required for analytics and crash reporting

   **Option A: Using VSCode (Recommended)**

   1. Open the project in VSCode with the Garmin Connect IQ extension
   2. Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux)
   3. Type and select `Monkey C: Configure Monkey Barrel`
   4. Download the [TinyMetrix](https://tinymetrix.com) barrel from: https://tinymetrix.com/assets/binaries/tinymetrix-2.1.6.barrel
   5. Select the downloaded `.barrel` file when prompted

   **Option B: Manual installation**

   1. Download the barrel: https://tinymetrix.com/assets/binaries/tinymetrix-2.1.6.barrel
   2. Create a `barrels` directory in your project root if it doesn't exist
   3. Copy `tinymetrix-2.1.6.barrel` to the `barrels/` folder
   4. The barrel is already configured in `manifest.xml`:
      ```xml
      <iq:barrels>
          <iq:depends name="Tinymetrix" version="2.1.6"/>
      </iq:barrels>
      ```

3. **Configure properties file**

   Copy the example properties file:
   ```bash
   cp resources/properties.xml.example resources/properties.xml
   ```

   The example file includes a `MOCK_TOKEN` that works for development. For production, edit `resources/properties.xml` and replace `MOCK_TOKEN` with your actual [TinyMetrix](https://tinymetrix.com) token.

### Proxy Backend

```bash
cd server
npm install
npm start        # runs on http://localhost:3000
```

Set the `PORT` environment variable to change the port.

**Deploy to production** (Railway, Render, Fly.io, Cloudflare Workers, etc.):
```monkey-c
// BiciMadService.mc — update these URLs after deploying
private const URL_PROXY  = "https://your-proxy.example.com/api/stations";
private const URL_TRIPS  = "https://your-proxy.example.com/api/trips";
private const URL_CHECK  = "https://your-proxy.example.com/api/check";
private const URL_UNLOCK = "https://your-proxy.example.com/api/unlock";
```

---

## Project Structure

```
bicimad/
├── source/                      # Monkey C source (watch app)
│   ├── bicimadApp.mc            # App entry point, token storage, session management
│   ├── bicimadView.mc           # Main menu (Menu2) + delegate
│   ├── BiciMadService.mc        # All API calls: login, stations, trips, check, unlock
│   ├── StationsData.mc          # Static station coordinates (auto-generated, 632 stations)
│   ├── StationListView.mc       # Station search: GPS proximity + name search
│   ├── LoginView.mc             # Login form (Menu2 + TextPicker)
│   ├── PlateSearchView.mc       # Unlock bike by plate: input → verify → confirm → result
│   ├── TripsView.mc             # Trip history + active trip detail
│   ├── ReservationView.mc       # Station booking flow
│   └── PositionManager.mc       # GPS location handler
├── resources/
│   ├── strings/strings.xml      # Default strings (English fallback)
│   ├── layouts/layout.xml       # Base layout
│   └── menus/menu.xml           # Menu resources
├── resources-eng/               # English UI strings
│   └── strings/strings.xml
├── resources-spa/               # Spanish UI strings
│   └── strings/strings.xml
├── server/                      # Proxy backend (Node.js)
│   ├── index.js                 # Express server — all 4 API endpoints
│   └── package.json
├── manifest.xml                 # App manifest (permissions, 140+ target devices)
└── monkey.jungle                # Build configuration
```

---

## License

MIT — see [LICENSE](LICENSE) for details.

This project is not affiliated with, endorsed by, or connected to EMT Madrid or Garmin.
