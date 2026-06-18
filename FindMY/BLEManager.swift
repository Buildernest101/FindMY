import Foundation
import CoreBluetooth
import Combine

// ─── CONFIGURE YOUR DEVICE ───────────────────────────────────────────────────
// Replace the placeholder below with your scooter/vehicle name.
// This must exactly match the DEVICE_NAME defined in your ESP32 firmware.
// Example: "Honda Activa 5420", "Royal Enfield", "My Bike"
let kDeviceName = "Your Vehicle Name"

// Your ESP32 UUIDs — must match SERVICE_UUID / CHARACTERISTIC_UUID in firmware
let esp32ServiceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let esp32CharacteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")
// ─────────────────────────────────────────────────────────────────────────────

struct ESP32DeviceInfo: Codable {
    let deviceId: String
    let location: String
}

class BLEManager: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var statusMessage: String = "Idle"
    @Published var deviceInfo: ESP32DeviceInfo?
    @Published var rssiValue: Int?

    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var rssiTimer: Timer?

    // Controls whether we should keep trying to reconnect
    private var shouldAutoReconnect = true

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        statusMessage = "Initializing Bluetooth..."
    }

    // MARK: - Public controls

    func startScan() {
        guard centralManager.state == .poweredOn else {
            DispatchQueue.main.async {
                self.statusMessage = "Bluetooth is not ON"
            }
            print("🔵 Cannot scan - Bluetooth not powered on")
            return
        }
        if isScanning {
            print("🔵 Already scanning, skipping")
            return
        }

        print("🔵 Starting scan for device...")
        
        DispatchQueue.main.async {
            self.statusMessage = "Scanning for \(kDeviceName)..."
            self.isScanning = true
        }

        centralManager.scanForPeripherals(
            withServices: [esp32ServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        centralManager.stopScan()
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }

    /// Called when user explicitly wants to disconnect
    func disconnect() {
        print("🔵 User requested disconnect")
        shouldAutoReconnect = false
        stopScan()
        stopRSSIPolling()

        if let peripheral = esp32Peripheral, isConnected {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        // Clear state immediately on main thread
        DispatchQueue.main.async {
            self.isConnected = false
            self.rssiValue = nil
            self.statusMessage = "Disconnected by user"
        }
    }

    /// Called when user taps to reconnect / connect
    func reconnect() {
        print("🔵 User requested reconnect")
        shouldAutoReconnect = true
        
        DispatchQueue.main.async {
            self.rssiValue = nil
        }
        
        startScan()
    }

    // MARK: - RSSI polling

    private func startRSSIPolling() {
        stopRSSIPolling()
        guard let peripheral = esp32Peripheral else { return }

        rssiTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            peripheral.readRSSI()
        }
    }

    private func stopRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            switch central.state {
            case .unknown:
                self.statusMessage = "Bluetooth state: unknown"
            case .resetting:
                self.statusMessage = "Bluetooth resetting"
            case .unsupported:
                self.statusMessage = "Bluetooth unsupported on this device"
            case .unauthorized:
                self.statusMessage = "Bluetooth unauthorized"
            case .poweredOff:
                self.statusMessage = "Bluetooth is OFF"
                self.isScanning = false
                self.isConnected = false
                self.stopRSSIPolling()
            case .poweredOn:
                self.statusMessage = "Bluetooth is ON"
                if self.shouldAutoReconnect {
                    self.startScan()
                }
            @unknown default:
                self.statusMessage = "Bluetooth unknown state"
            }
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let name = peripheral.name ?? "Unknown"
        print("🔵 Discovered: \(name), RSSI: \(RSSI)")

        // Update state on main thread - keep isScanning=true to avoid "Disconnected" flash
        DispatchQueue.main.async {
            self.statusMessage = "Found \(name). Connecting..."
            self.rssiValue = RSSI.intValue
            // Don't set isScanning = false here - wait until connected
        }
        
        centralManager.stopScan()

        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self

        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        print("🔵 Successfully connected to peripheral")
        
        // Update UI state on main thread explicitly
        DispatchQueue.main.async {
            self.statusMessage = "Connected to \(peripheral.name ?? kDeviceName)"
            self.isConnected = true
            self.isScanning = false
        }

        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self

        startRSSIPolling()
        peripheral.discoverServices([esp32ServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("🔵 Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        
        DispatchQueue.main.async {
            self.statusMessage = "Failed to connect: \(error?.localizedDescription ?? "unknown error")"
            self.isConnected = false
            self.isScanning = false  // Reset scanning state on failure
        }
        
        stopRSSIPolling()

        if shouldAutoReconnect {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("🔵 Disconnected, shouldAutoReconnect=\(shouldAutoReconnect)")
        
        DispatchQueue.main.async {
            self.statusMessage = "Disconnected"
            self.isConnected = false
            self.isScanning = false  // Reset scanning state
            self.rssiValue = nil
        }
        
        esp32Peripheral = nil
        stopRSSIPolling()

        if shouldAutoReconnect {
            startScan()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            statusMessage = "Service discovery error: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == esp32ServiceUUID {
                statusMessage = "Service found. Discovering characteristics..."
                peripheral.discoverCharacteristics([esp32CharacteristicUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {

        if let error = error {
            statusMessage = "Characteristic discovery error: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == esp32CharacteristicUUID {
                statusMessage = "Characteristic found. Reading value..."
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        if let error = error {
            statusMessage = "Read error: \(error.localizedDescription)"
            return
        }

        guard let data = characteristic.value,
              let string = String(data: data, encoding: .utf8) else {
            statusMessage = "Invalid data from \(kDeviceName)"
            return
        }

        print("Received raw value: \(string)")
        statusMessage = "Data received"

        if let jsonData = string.data(using: .utf8) {
            do {
                let decoded = try JSONDecoder().decode(ESP32DeviceInfo.self, from: jsonData)
                DispatchQueue.main.async {
                    self.deviceInfo = decoded
                }
            } catch {
                print("JSON parse error: \(error)")
                statusMessage = "Failed to parse JSON"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didReadRSSI RSSI: NSNumber,
                    error: Error?) {
        if let error = error {
            print("RSSI read error: \(error.localizedDescription)")
            return
        }

        DispatchQueue.main.async {
            self.rssiValue = RSSI.intValue
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            statusMessage = "Notify state error: \(error.localizedDescription)"
        }
    }
}
