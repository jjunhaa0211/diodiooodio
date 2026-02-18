import AudioToolbox
import CoreAudio
import Foundation

protocol AudioHardwareControlling: AnyObject {
    func outputDevices() throws -> [AudioDevice]
    func defaultOutputDeviceID() throws -> AudioDeviceID
    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) throws
    func systemVolume() throws -> Float
    func setSystemVolume(_ value: Float) throws
    func startObservingChanges(_ onChange: @escaping @Sendable () -> Void)
    func stopObservingChanges()
}

enum AudioHardwareError: Error, LocalizedError {
    case coreAudio(OSStatus)
    case deviceNotFound
    case volumeControlUnsupported

    var errorDescription: String? {
        switch self {
        case .coreAudio(let status):
            return "CoreAudio error (\(status))."
        case .deviceNotFound:
            return "Output device not found."
        case .volumeControlUnsupported:
            return "Volume control is not supported on this device."
        }
    }
}

final class CoreAudioService: AudioHardwareControlling {
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let listenerQueue = DispatchQueue(label: "odioodiodio.coreaudio.listener")
    private let observedSystemAddresses: [AudioObjectPropertyAddress] = [
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        ),
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        ),
    ]

    private lazy var systemListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] addressCount, addresses in
        guard let self else { return }

        for index in 0 ..< Int(addressCount) {
            let selector = addresses[index].mSelector
            if selector == kAudioHardwarePropertyDefaultOutputDevice {
                self.rebindVolumeListeners()
                break
            }
        }
        self.notifyChange()
    }

    private lazy var volumeListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.notifyChange()
    }

    private var observedVolumeDeviceID: AudioDeviceID?
    private var observedVolumeAddresses: [AudioObjectPropertyAddress] = []
    private var isObserving = false
    private var onChange: (@Sendable () -> Void)?

    func outputDevices() throws -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            throw AudioHardwareError.coreAudio(sizeStatus)
        }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID.zero, count: deviceCount)
        let dataStatus = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &deviceIDs)
        guard dataStatus == noErr else {
            throw AudioHardwareError.coreAudio(dataStatus)
        }

        let defaultDevice = try? defaultOutputDeviceID()

        let devices: [AudioDevice] = deviceIDs.compactMap { deviceID in
            guard outputChannelCount(for: deviceID) > 0 else { return nil }
            let name = deviceName(for: deviceID)
            let sampleRate = nominalSampleRate(for: deviceID)
            let channels = outputChannelCount(for: deviceID)
            let transport = transportType(for: deviceID)

            return AudioDevice(
                id: deviceID,
                name: name,
                transport: transport,
                isDefault: defaultDevice == deviceID,
                sampleRate: sampleRate,
                channels: channels
            )
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var outputDeviceID = AudioDeviceID.zero
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &outputDeviceID)
        guard status == noErr else {
            throw AudioHardwareError.coreAudio(status)
        }
        guard outputDeviceID != AudioDeviceID.zero else {
            throw AudioHardwareError.deviceNotFound
        }
        return outputDeviceID
    }

    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(systemObjectID, &address, 0, nil, size, &mutableDeviceID)
        guard status == noErr else {
            throw AudioHardwareError.coreAudio(status)
        }
    }

    func systemVolume() throws -> Float {
        let deviceID = try defaultOutputDeviceID()
        let addresses = volumeAddresses(for: deviceID)
        guard let address = addresses.first else {
            throw AudioHardwareError.volumeControlUnsupported
        }

        var mutableAddress = address
        var volume = Float32.zero
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &mutableAddress, 0, nil, &size, &volume)
        guard status == noErr else {
            throw AudioHardwareError.coreAudio(status)
        }
        return max(0, min(1, volume))
    }

    func setSystemVolume(_ value: Float) throws {
        let deviceID = try defaultOutputDeviceID()
        let addresses = volumeAddresses(for: deviceID)
        guard !addresses.isEmpty else {
            throw AudioHardwareError.volumeControlUnsupported
        }

        let normalized = Float32(max(0, min(1, value)))
        let size = UInt32(MemoryLayout<Float32>.size)

        for address in addresses {
            var mutableAddress = address
            var mutableVolume = normalized
            let status = AudioObjectSetPropertyData(
                deviceID,
                &mutableAddress,
                0,
                nil,
                size,
                &mutableVolume
            )
            guard status == noErr else {
                throw AudioHardwareError.coreAudio(status)
            }
        }
    }

    func startObservingChanges(_ onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        guard !isObserving else { return }

        for address in observedSystemAddresses {
            var mutableAddress = address
            AudioObjectAddPropertyListenerBlock(
                systemObjectID,
                &mutableAddress,
                listenerQueue,
                systemListenerBlock
            )
        }

        isObserving = true
        rebindVolumeListeners()
    }

    func stopObservingChanges() {
        guard isObserving else { return }

        for address in observedSystemAddresses {
            var mutableAddress = address
            AudioObjectRemovePropertyListenerBlock(
                systemObjectID,
                &mutableAddress,
                listenerQueue,
                systemListenerBlock
            )
        }

        removeVolumeListeners()
        isObserving = false
        onChange = nil
    }

    private func notifyChange() {
        guard let onChange else { return }
        DispatchQueue.main.async(execute: onChange)
    }

    private func rebindVolumeListeners() {
        removeVolumeListeners()
        guard let deviceID = try? defaultOutputDeviceID() else { return }

        let addresses = volumeAddresses(for: deviceID)
        guard !addresses.isEmpty else { return }

        observedVolumeDeviceID = deviceID
        observedVolumeAddresses = addresses

        for address in addresses {
            var mutableAddress = address
            AudioObjectAddPropertyListenerBlock(
                deviceID,
                &mutableAddress,
                listenerQueue,
                volumeListenerBlock
            )
        }
    }

    private func removeVolumeListeners() {
        guard let deviceID = observedVolumeDeviceID else { return }

        for address in observedVolumeAddresses {
            var mutableAddress = address
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &mutableAddress,
                listenerQueue,
                volumeListenerBlock
            )
        }

        observedVolumeDeviceID = nil
        observedVolumeAddresses = []
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanagedName else { return "Unknown Device" }
        return unmanagedName.takeUnretainedValue() as String
    }

    private func nominalSampleRate(for deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        guard status == noErr else { return 0 }
        return sampleRate
    }

    private func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard sizeStatus == noErr, size > 0 else { return 0 }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
        guard dataStatus == noErr else { return 0 }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func transportType(for deviceID: AudioDeviceID) -> AudioDevice.Transport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transport = UInt32.zero
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        guard status == noErr else { return .unknown }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeAirPlay:
            return .airPlay
        case kAudioDeviceTransportTypeAggregate:
            return .aggregate
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        case kAudioDeviceTransportTypePCI:
            return .pci
        case kAudioDeviceTransportTypeFireWire:
            return .fireWire
        case kAudioDeviceTransportTypeThunderbolt:
            return .thunderbolt
        default:
            return .unknown
        }
    }

    private func volumeAddresses(for deviceID: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        let candidates: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]
        let available: [AudioObjectPropertyAddress] = candidates.compactMap { channel in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: channel
            )
            return AudioObjectHasProperty(deviceID, &address) ? address : nil
        }

        if let master = available.first(where: { $0.mElement == kAudioObjectPropertyElementMain }) {
            return [master]
        }

        return available.sorted(by: { $0.mElement < $1.mElement })
    }
}
