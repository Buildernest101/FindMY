import Foundation
import CoreBluetooth
import Combine

// Your ESP32 UUIDs
let esp32ServiceUUID = CBUUID(string: "4fafc201-1fb5-459e-8fcc-c5c9c331914b")
let esp32CharacteristicUUID = CBUUID(string: "beb5483e-36e1-4688-b7f5-ea07361b26a8")

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

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        statusMessage = "Initializing Bluetooth..."
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth is not ON"
            return
        }

        statusMessage = "Scanning for ESP32..."
        isScanning = true

        // Scan for peripherals exposing your service
        centralManager.scanForPeripherals(
            withServices: [esp32ServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = "Scan stopped"
    }

    func disconnect() {
        if let peripheral = esp32Peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            statusMessage = "Bluetooth state: unknown"
        case .resetting:
            statusMessage = "Bluetooth resetting"
        case .unsupported:
            statusMessage = "Bluetooth unsupported"
        case .unauthorized:
            statusMessage = "Bluetooth unauthorized"
        case .poweredOff:
            statusMessage = "Bluetooth is OFF"
        case .poweredOn:
            statusMessage = "Bluetooth is ON. Tap Scan."
        @unknown default:
            statusMessage = "Bluetooth unknown state"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let name = peripheral.name ?? "Unknown"
        print("Discovered: \(name), RSSI: \(RSSI)")

        statusMessage = "Found \(name). Connecting..."
        isScanning = false
        centralManager.stopScan()

        esp32Peripheral = peripheral
        esp32Peripheral?.delegate = self
        rssiValue = RSSI.intValue

        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        statusMessage = "Connected to \(peripheral.name ?? "ESP32")"
        isConnected = true
        peripheral.discoverServices([esp32ServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        statusMessage = "Failed to connect: \(error?.localizedDescription ?? "unknown error")"
        isConnected = false
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        statusMessage = "Disconnected"
        isConnected = false
        deviceInfo = nil
        rssiValue = nil
    }
}

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
            statusMessage = "Invalid data from ESP32"
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
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            statusMessage = "Notify state error: \(error.localizedDescription)"
        }
    }
}
