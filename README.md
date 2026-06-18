# FUBLE — Find My Scooter

An iOS app that uses **Bluetooth Low Energy (BLE)** to help you locate your scooter (Honda Activa). When your phone disconnects from the scooter's ESP32 device, it automatically saves your GPS location so you can navigate back to it.

---

## Features

- **BLE proximity radar** — visual halo + dot moves closer as RSSI improves
- **Auto-saves parked location** — GPS coordinates stored the moment your scooter disconnects
- **"Parked" button** — one tap opens Apple Maps to navigate back
- **Device info sheet** — shows device ID and live signal strength
- **Auto-reconnect** — app resumes scanning after Bluetooth restarts or disconnect

---

## Requirements

| Requirement | Version |
|---|---|
| iOS | 16.0+ |
| Xcode | 15.0+ |
| Swift | 5.9+ |
| Hardware | iPhone with Bluetooth 4.0+ |

---

## Hardware Setup (ESP32)

The app connects to an **ESP32** running a BLE GATT server. Flash your ESP32 with firmware that:

1. Advertises the service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
2. Exposes a characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8`
3. Sends JSON over that characteristic in this format:

```json
{
  "deviceId": "ACTIVA-5420",
  "location": "scooter"
}
```

> **Note:** The UUIDs above are the default pairing identifiers. If you change them on the ESP32 side, update `BLEManager.swift` lines 6–7 to match.

---

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/<your-username>/FindMY.git
cd FindMY
```

### 2. Open in Xcode

```bash
open FindMy.xcodeproj
```

Or double-click `FindMy.xcodeproj` in Finder.

### 3. Configure signing

1. Select the `FindMY` target in Xcode
2. Go to **Signing & Capabilities**
3. Set your **Team** (Apple Developer account)
4. Change the **Bundle Identifier** to something unique, e.g. `com.yourname.fuble`

### 4. Add required permissions to `Info.plist`

The following keys must be present (Xcode may auto-add them — verify they exist):

| Key | Purpose |
|---|---|
| `NSBluetoothAlwaysUsageDescription` | Scanning for the ESP32 device |
| `NSLocationWhenInUseUsageDescription` | Saving parked location on disconnect |

Example values:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>FUBLE uses Bluetooth to find your scooter.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>FUBLE saves your location when your scooter disconnects so you can find it later.</string>
```

### 5. Build and run

- Connect your iPhone via USB (BLE and GPS require a real device — simulator won't work)
- Select your device in the Xcode toolbar
- Press **⌘R** to build and run

---

## Customising Your Device Name

The app is hardcoded to display **"Activa • 5420"**. To rename it, search for that string in `ContentView.swift` and replace it with your scooter's name.

---

## Project Structure

```
FindMY/
├── FindMy/
│   ├── FUBLE.swift            # App entry point
│   ├── ContentView.swift      # Main UI + parking logic
│   ├── BLEManager.swift       # CoreBluetooth scanning & connection
│   ├── LocationManager.swift  # CoreLocation GPS tracking
│   ├── ProximityModel.swift   # RSSI → proximity level mapping
│   └── Assets.xcassets/       # App icon, scooter images
├── FindMyTests/
└── FindMyUITests/
```

---

## Security Notes

- No API keys, passwords, or tokens are stored in this codebase.
- The BLE UUIDs are device-pairing identifiers, not secrets — they must match your ESP32 firmware.
- Parked location is stored in iOS `UserDefaults` (via `@AppStorage`) — it never leaves your device.
- `xcuserdata/` (personal Xcode settings) is excluded via `.gitignore`.

---

## License

MIT — free to use and modify.
