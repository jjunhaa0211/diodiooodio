import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let transport: Transport
    let isDefault: Bool
    let sampleRate: Double
    let channels: Int

    var detailText: String {
        "\(transport.rawValue) | \(Int(sampleRate)) Hz | \(channels) ch"
    }

    enum Transport: String, Hashable {
        case builtIn = "Built-in"
        case usb = "USB"
        case bluetooth = "Bluetooth"
        case airPlay = "AirPlay"
        case aggregate = "Aggregate"
        case virtual = "Virtual"
        case pci = "PCI"
        case fireWire = "FireWire"
        case thunderbolt = "Thunderbolt"
        case unknown = "Unknown"
    }
}
