// FUBLE — ESP32 BLE Firmware
// Pairs with the FUBLE iOS app (FindMY project)
//
// Requirements:
//   - Arduino IDE 2.x or PlatformIO
//   - ESP32 board package: https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
//   - ArduinoJson library v6+ (install via Library Manager)
//   - Board target: "ESP32 Dev Module"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// ─── CONFIGURE YOUR DEVICE ───────────────────────────────────────────────────
// Replace the placeholder below with your vehicle name.
// This must exactly match kDeviceName in BLEManager.swift on the iOS side.
// Example: "Honda Activa 5420", "Royal Enfield", "My Bike"
#define DEVICE_NAME "Your Vehicle Name"

// Device ID sent inside the JSON payload — shown in the app's Device Info sheet.
// Can be any unique identifier for your ESP32 unit.
// Example: "ACTIVA-5420", "RE-BULLET-01"
#define DEVICE_ID   "YOUR-DEVICE-ID"

// UUIDs — must match esp32ServiceUUID / esp32CharacteristicUUID in BLEManager.swift.
// Only change these if you regenerate your own UUIDs on both sides simultaneously.
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
// ─────────────────────────────────────────────────────────────────────────────

// ─── OPTIMISATION TUNABLES ───────────────────────────────────────────────────
// Advertising interval (ms) — lower = iPhone discovers faster, higher = less power.
// 100ms gives near-instant discovery. Increase to 500ms to save ESP32 battery.
#define ADV_INTERVAL_MS       100

// How often (ms) the ESP32 pushes a BLE notify to the connected iPhone.
// 500ms keeps the proximity radar smooth. Raise to 1000ms to reduce radio traffic.
#define NOTIFY_INTERVAL_MS    500
// ─────────────────────────────────────────────────────────────────────────────

BLEServer*         pServer         = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool               deviceConnected = false;
unsigned long      lastNotify      = 0;

// Builds the JSON payload decoded by the iOS app into ESP32DeviceInfo
String buildPayload() {
    StaticJsonDocument<128> doc;
    doc["deviceId"] = DEVICE_ID;
    doc["location"] = "scooter";
    String output;
    serializeJson(doc, output);
    return output;
}

class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        deviceConnected = true;
        Serial.println("[BLE] iPhone connected");
    }

    void onDisconnect(BLEServer* pServer) override {
        deviceConnected = false;
        Serial.println("[BLE] iPhone disconnected — restarting advertising");
        // Restart so the iOS app can auto-reconnect
        BLEDevice::startAdvertising();
    }
};

class CharacteristicCallbacks : public BLECharacteristicCallbacks {
    // Fires when iOS calls peripheral.readValue(for:)
    void onRead(BLECharacteristic* pCharacteristic) override {
        String payload = buildPayload();
        pCharacteristic->setValue(payload.c_str());
        Serial.println("[BLE] Read request — sent: " + payload);
    }
};

void setup() {
    Serial.begin(115200);
    Serial.println("[FUBLE] Starting up...");

    // Set TX power to maximum for best range (~+9 dBm on most ESP32 modules)
    esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_ADV, ESP_PWR_LVL_P9);
    esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_DEFAULT, ESP_PWR_LVL_P9);

    BLEDevice::init(DEVICE_NAME);
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    BLEService* pService = pServer->createService(SERVICE_UUID);

    pCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );

    // BLE2902 descriptor enables the iOS app's setNotifyValue(true, for:) call
    pCharacteristic->addDescriptor(new BLE2902());
    pCharacteristic->setCallbacks(new CharacteristicCallbacks());

    // Set initial value before advertising
    String payload = buildPayload();
    pCharacteristic->setValue(payload.c_str());

    pService->start();

    // Configure fast advertising so iPhone discovers device quickly
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);

    uint16_t advIntervalUnits = (ADV_INTERVAL_MS * 1000) / 625; // convert ms → 0.625ms units
    pAdvertising->setMinInterval(advIntervalUnits);
    pAdvertising->setMaxInterval(advIntervalUnits);

    BLEDevice::startAdvertising();
    Serial.println("[BLE] Advertising as: " + String(DEVICE_NAME));
}

void loop() {
    if (!deviceConnected) return;

    unsigned long now = millis();
    if (now - lastNotify >= NOTIFY_INTERVAL_MS) {
        String payload = buildPayload();
        pCharacteristic->setValue(payload.c_str());
        pCharacteristic->notify();
        lastNotify = now;
    }
}
