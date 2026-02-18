import AudioToolbox
import os

final class ProcessTapController {
    let app: AudioApp
    private let logger: Logger
    private let queue = DispatchQueue(label: "ProcessTapController", qos: .userInitiated)

    /// 장치 모니터 값입니다.
    private weak var deviceMonitor: AudioDeviceMonitor?

    // MARK: - 볼륨

    /// 볼륨 값입니다.
    private nonisolated(unsafe) var _volume: Float = 1.0
    /// 기본 현재 볼륨 값입니다.
    private nonisolated(unsafe) var _primaryCurrentVolume: Float = 1.0
    /// 보조 현재 볼륨 값입니다.
    private nonisolated(unsafe) var _secondaryCurrentVolume: Float = 1.0
    /// 강제 무음 상태를 나타냅니다.
    private nonisolated(unsafe) var _forceSilence: Bool = false
    /// 음소거 여부를 나타냅니다.
    private nonisolated(unsafe) var _isMuted: Bool = false
    /// 장치 볼륨 보정 값입니다.
    private nonisolated(unsafe) var _deviceVolumeCompensation: Float = 1.0
    /// 피크 레벨 값입니다.
    private nonisolated(unsafe) var _peakLevel: Float = 0.0
    private nonisolated(unsafe) var _currentDeviceVolume: Float = 1.0
    private nonisolated(unsafe) var _isDeviceMuted: Bool = false

    private nonisolated(unsafe) var _crossfadeProgress: Float = 0
    private nonisolated(unsafe) var _isCrossfading: Bool = false
    /// 보조 샘플 개수 개수입니다.
    private nonisolated(unsafe) var _secondarySampleCount: Int64 = 0
    private nonisolated(unsafe) var _crossfadeTotalSamples: Int64 = 0
    /// 보조 샘플 처리된 값입니다.
    private nonisolated(unsafe) var _secondarySamplesProcessed: Int = 0

    // MARK: - 레벨 smoothing

    /// 레벨 완화 계수 값입니다.
    private let levelSmoothingFactor: Float = 0.3
    /// ramp 계수 값입니다.
    private var rampCoefficient: Float = 0.0007
    private var secondaryRampCoefficient: Float = 0.0007
    /// minimum 워밍업 샘플 개수입니다.
    private let minimumWarmupSamples: Int = 2048

    private var eqProcessor: EQProcessor?

    private var targetDeviceUIDs: [String]
    private(set) var currentDeviceUIDs: [String] = []

    /// 현재 장치 UID 식별자입니다.
    var currentDeviceUID: String? { currentDeviceUIDs.first }

    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var tapDescription: CATapDescription?
    private var activated = false

    private var secondaryTapID: AudioObjectID = .unknown
    private var secondaryAggregateID: AudioObjectID = .unknown
    private var secondaryDeviceProcID: AudioDeviceIOProcID?
    private var secondaryTapDescription: CATapDescription?

    // MARK: - 오디오

    var audioLevel: Float { _peakLevel }

    var currentDeviceVolume: Float {
        get { _currentDeviceVolume }
        set { _currentDeviceVolume = newValue }
    }

    var isDeviceMuted: Bool {
        get { _isDeviceMuted }
        set { _isDeviceMuted = newValue }
    }

    var volume: Float {
        get { _volume }
        set { _volume = newValue }
    }

    var isMuted: Bool {
        get { _isMuted }
        set { _isMuted = newValue }
    }

    // MARK: - 초기화

    /// 내부 동작을 담당합니다.
    init(app: AudioApp, targetDeviceUIDs: [String], deviceMonitor: AudioDeviceMonitor? = nil) {
        precondition(!targetDeviceUIDs.isEmpty, "Must have at least one target device")
        self.app = app
        self.targetDeviceUIDs = targetDeviceUIDs
        self.deviceMonitor = deviceMonitor
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "diodiooodio", category: "ProcessTapController(\(app.name))")
    }

    /// 내부 동작을 담당합니다.
    convenience init(app: AudioApp, targetDeviceUID: String, deviceMonitor: AudioDeviceMonitor? = nil) {
        self.init(app: app, targetDeviceUIDs: [targetDeviceUID], deviceMonitor: deviceMonitor)
    }

    // MARK: - 갱신 eqsettings

    func updateEQSettings(_ settings: EQSettings) {
        eqProcessor?.updateSettings(settings)
    }

    // MARK: - build aggregate

    /// build aggregate description 동작을 처리합니다.
    private func buildAggregateDescription(outputUIDs: [String], tapUUID: UUID, name: String) -> [String: Any] {
        precondition(!outputUIDs.isEmpty, "Must have at least one output device")

        var subDevices: [[String: Any]] = []
        for (index, deviceUID) in outputUIDs.enumerated() {
            subDevices.append([
                kAudioSubDeviceUIDKey: deviceUID,
                kAudioSubDeviceDriftCompensationKey: index > 0
            ])
        }

        let clockDeviceUID = outputUIDs[0]

        return [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: clockDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: clockDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString
                ]
            ]
        ]
    }

    func activate() throws {
        guard !activated else { return }

        logger.debug("Activating tap for \(self.app.name)")

        let tapDesc = CATapDescription(stereoMixdownOfProcesses: [app.objectID])
        tapDesc.uuid = UUID()
        tapDesc.muteBehavior = .mutedWhenTapped
        self.tapDescription = tapDesc

        var tapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard err == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to create process tap: \(err)"])
        }

        processTapID = tapID
        logger.debug("Created process tap #\(tapID)")

        let description = buildAggregateDescription(
            outputUIDs: targetDeviceUIDs,
            tapUUID: tapDesc.uuid,
            name: "diodiooodio-\(app.id)"
        )

        aggregateDeviceID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            cleanupPartialActivation()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to create aggregate device: \(err)"])
        }

        guard aggregateDeviceID.waitUntilReady(timeout: 2.0) else {
            cleanupPartialActivation()
            throw NSError(domain: "ProcessTapController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Aggregate device not ready within timeout"])
        }

        logger.debug("Created aggregate device #\(self.aggregateDeviceID)")

        let sampleRate: Float64
        if let deviceSampleRate = try? aggregateDeviceID.readNominalSampleRate() {
            sampleRate = deviceSampleRate
            logger.info("Device sample rate: \(sampleRate) Hz")
        } else {
            sampleRate = 48000
            logger.warning("Failed to read sample rate, using default: \(sampleRate) Hz")
        }
        let rampTimeSeconds: Float = 0.030
        rampCoefficient = 1 - exp(-1 / (Float(sampleRate) * rampTimeSeconds))
        logger.debug("Ramp coefficient: \(self.rampCoefficient)")

        eqProcessor = EQProcessor(sampleRate: sampleRate)

        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self else { return }
            self.processAudio(inInputData, to: outOutputData)
        }
        guard err == noErr else {
            cleanupPartialActivation()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to create IO proc: \(err)"])
        }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else {
            cleanupPartialActivation()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to start device: \(err)"])
        }

        _primaryCurrentVolume = _volume
        _deviceVolumeCompensation = 1.0

        currentDeviceUIDs = targetDeviceUIDs

        activated = true
        logger.info("Tap activated for \(self.app.name) on \(self.targetDeviceUIDs.count) device(s)")
    }

    /// 장치을(를) 전환합니다
    func switchDevice(to newDeviceUID: String) async throws {
        try await updateDevices(to: [newDeviceUID])
    }

    /// 장치을(를) 갱신합니다
    func updateDevices(to newDeviceUIDs: [String]) async throws {
        precondition(!newDeviceUIDs.isEmpty, "Must have at least one target device")

        guard activated else {
            targetDeviceUIDs = newDeviceUIDs
            return
        }

        guard newDeviceUIDs != currentDeviceUIDs else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("[UPDATE] Switching \(self.app.name) to \(newDeviceUIDs.count) device(s)")

        let primaryDeviceUID = newDeviceUIDs[0]

        do {
            try await performCrossfadeSwitch(to: primaryDeviceUID, allDeviceUIDs: newDeviceUIDs)
        } catch {
            logger.warning("[UPDATE] Crossfade failed: \(error.localizedDescription), using fallback")
            guard tapDescription != nil else {
                throw CrossfadeError.noTapDescription
            }
            try await performDestructiveDeviceSwitch(to: primaryDeviceUID, allDeviceUIDs: newDeviceUIDs)
        }

        targetDeviceUIDs = newDeviceUIDs
        currentDeviceUIDs = newDeviceUIDs

        let endTime = CFAbsoluteTimeGetCurrent()
        logger.info("[UPDATE] === END === Total time: \((endTime - startTime) * 1000)ms")
    }

    /// invalidate 동작을 처리합니다.
    func invalidate() {
        guard activated else { return }
        activated = false

        logger.debug("Invalidating tap for \(self.app.name)")

        _isCrossfading = false

        let primaryAggregate = aggregateDeviceID
        let primaryProcID = deviceProcID
        let primaryTap = processTapID
        let secAggregate = secondaryAggregateID
        let secProcID = secondaryDeviceProcID
        let secTap = secondaryTapID

        aggregateDeviceID = .unknown
        deviceProcID = nil
        processTapID = .unknown
        secondaryAggregateID = .unknown
        secondaryDeviceProcID = nil
        secondaryTapID = .unknown
        secondaryTapDescription = nil

        DispatchQueue.global(qos: .utility).async {
            CrossfadeOrchestrator.destroyTap(aggregateID: secAggregate, deviceProcID: secProcID, tapID: secTap)
            CrossfadeOrchestrator.destroyTap(aggregateID: primaryAggregate, deviceProcID: primaryProcID, tapID: primaryTap)
        }

        logger.info("Tap invalidated for \(self.app.name)")
    }

    deinit {
        invalidate()
    }

    // MARK: - perform crossfade

    private func performCrossfadeSwitch(to primaryDeviceUID: String, allDeviceUIDs: [String]? = nil) async throws {
        let deviceUIDs = allDeviceUIDs ?? [primaryDeviceUID]

        logger.info("[CROSSFADE] Step 1: Reading device volumes for compensation")

        var isBluetoothDestination = false
        if let destDevice = deviceMonitor?.device(for: primaryDeviceUID) {
            let transport = destDevice.id.readTransportType()
            isBluetoothDestination = (transport == .bluetooth || transport == .bluetoothLE)
            logger.debug("[CROSSFADE] Destination device: BT=\(isBluetoothDestination)")
        }

        logger.info("[CROSSFADE] Step 2: Preparing crossfade state")

        _crossfadeProgress = 0
        _secondarySampleCount = 0
        _secondarySamplesProcessed = 0
        _isCrossfading = true

        logger.info("[CROSSFADE] Step 3: Creating secondary tap for \(deviceUIDs.count) device(s)")
        try createSecondaryTap(for: deviceUIDs)

        if isBluetoothDestination {
            logger.info("[CROSSFADE] Destination is Bluetooth - using extended warmup")
        }

        let warmupMs = isBluetoothDestination ? 300 : 50
        logger.info("[CROSSFADE] Step 4: Waiting for secondary tap warmup (\(warmupMs)ms)...")
        try await Task.sleep(for: .milliseconds(UInt64(warmupMs)))

        logger.info("[CROSSFADE] Step 5: Crossfade in progress (\(CrossfadeConfig.duration * 1000)ms)")

        let timeoutMs = Int(CrossfadeConfig.duration * 1000) + (isBluetoothDestination ? 400 : 100)
        let pollIntervalMs: UInt64 = 5
        var elapsedMs: Int = 0

        while (_crossfadeProgress < 1.0 || _secondarySamplesProcessed < minimumWarmupSamples) && elapsedMs < timeoutMs {
            try await Task.sleep(for: .milliseconds(pollIntervalMs))
            elapsedMs += Int(pollIntervalMs)
        }

        let progressAtTimeout = _crossfadeProgress
        if progressAtTimeout < 1.0 {
            logger.warning("[CROSSFADE] Timeout at \(progressAtTimeout * 100)% - forcing completion")
            _crossfadeProgress = 1.0
        }

        guard secondaryAggregateID.isValid, secondaryDeviceProcID != nil else {
            logger.error("[CROSSFADE] Secondary tap invalid after timeout")
            _isCrossfading = false
            throw CrossfadeError.secondaryTapFailed
        }

        try await Task.sleep(for: .milliseconds(10))

        logger.info("[CROSSFADE] Crossfade complete, promoting secondary")

        destroyPrimaryTap()
        promoteSecondaryToPrimary()

        _isCrossfading = false

        logger.info("[CROSSFADE] Complete")
    }

    private func createSecondaryTap(for outputUIDs: [String]) throws {
        precondition(!outputUIDs.isEmpty, "Must have at least one output device")

        let tapDesc = CATapDescription(stereoMixdownOfProcesses: [app.objectID])
        tapDesc.uuid = UUID()
        tapDesc.muteBehavior = .mutedWhenTapped
        secondaryTapDescription = tapDesc

        var tapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard err == noErr else {
            throw CrossfadeError.tapCreationFailed(err)
        }
        secondaryTapID = tapID
        logger.debug("[CROSSFADE] Created secondary tap #\(tapID)")

        let description = buildAggregateDescription(
            outputUIDs: outputUIDs,
            tapUUID: tapDesc.uuid,
            name: "diodiooodio-\(app.id)-secondary"
        )

        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &secondaryAggregateID)
        guard err == noErr else {
            AudioHardwareDestroyProcessTap(secondaryTapID)
            secondaryTapID = .unknown
            throw CrossfadeError.aggregateCreationFailed(err)
        }

        guard secondaryAggregateID.waitUntilReady(timeout: 2.0) else {
            AudioHardwareDestroyAggregateDevice(secondaryAggregateID)
            AudioHardwareDestroyProcessTap(secondaryTapID)
            secondaryAggregateID = .unknown
            secondaryTapID = .unknown
            throw CrossfadeError.deviceNotReady
        }

        logger.debug("[CROSSFADE] Created secondary aggregate #\(self.secondaryAggregateID)")

        let sampleRate: Double
        if let deviceSampleRate = try? secondaryAggregateID.readNominalSampleRate() {
            sampleRate = deviceSampleRate
        } else {
            sampleRate = 48000
        }
        _crossfadeTotalSamples = CrossfadeConfig.totalSamples(at: sampleRate)

        let rampTimeSeconds: Float = 0.030
        secondaryRampCoefficient = 1 - exp(-1 / (Float(sampleRate) * rampTimeSeconds))

        _secondaryCurrentVolume = _primaryCurrentVolume

        err = AudioDeviceCreateIOProcIDWithBlock(&secondaryDeviceProcID, secondaryAggregateID, queue) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self else { return }
            self.processAudioSecondary(inInputData, to: outOutputData)
        }
        guard err == noErr else {
            AudioHardwareDestroyAggregateDevice(secondaryAggregateID)
            AudioHardwareDestroyProcessTap(secondaryTapID)
            secondaryAggregateID = .unknown
            secondaryTapID = .unknown
            throw CrossfadeError.tapCreationFailed(err)
        }

        err = AudioDeviceStart(secondaryAggregateID, secondaryDeviceProcID)
        guard err == noErr else {
            if let procID = secondaryDeviceProcID {
                AudioDeviceDestroyIOProcID(secondaryAggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(secondaryAggregateID)
            AudioHardwareDestroyProcessTap(secondaryTapID)
            secondaryDeviceProcID = nil
            secondaryAggregateID = .unknown
            secondaryTapID = .unknown
            throw CrossfadeError.tapCreationFailed(err)
        }

        logger.debug("[CROSSFADE] Secondary tap started")
    }

    private func destroyPrimaryTap() {
        CrossfadeOrchestrator.destroyTap(aggregateID: aggregateDeviceID, deviceProcID: deviceProcID, tapID: processTapID)
        deviceProcID = nil
        aggregateDeviceID = .unknown
        processTapID = .unknown
        tapDescription = nil
    }

    private func promoteSecondaryToPrimary() {
        processTapID = secondaryTapID
        aggregateDeviceID = secondaryAggregateID
        deviceProcID = secondaryDeviceProcID
        tapDescription = secondaryTapDescription

        if let deviceSampleRate = try? aggregateDeviceID.readNominalSampleRate() {
            let rampTimeSeconds: Float = 0.030
            rampCoefficient = 1 - exp(-1 / (Float(deviceSampleRate) * rampTimeSeconds))
            eqProcessor?.updateSampleRate(deviceSampleRate)
        }

        _primaryCurrentVolume = _secondaryCurrentVolume
        _secondaryCurrentVolume = 0

        _crossfadeProgress = 0
        _secondarySampleCount = 0
        _crossfadeTotalSamples = 0

        secondaryTapID = .unknown
        secondaryAggregateID = .unknown
        secondaryDeviceProcID = nil
        secondaryTapDescription = nil
    }

    private func performDestructiveDeviceSwitch(to primaryDeviceUID: String, allDeviceUIDs: [String]? = nil) async throws {
        let deviceUIDs = allDeviceUIDs ?? [primaryDeviceUID]
        let originalVolume = _volume

        _forceSilence = true
        logger.info("[SWITCH-DESTROY] Enabled _forceSilence=true")

        try await Task.sleep(for: .milliseconds(100))

        try performDeviceSwitch(to: deviceUIDs)

        _primaryCurrentVolume = 0
        _volume = 0

        try await Task.sleep(for: .milliseconds(150))

        _forceSilence = false

        for i in 1...10 {
            _volume = originalVolume * Float(i) / 10.0
            try await Task.sleep(for: .milliseconds(20))
        }

        logger.info("[SWITCH-DESTROY] Complete")
    }

    private func performDeviceSwitch(to outputUIDs: [String]) throws {
        precondition(!outputUIDs.isEmpty, "Must have at least one output device")

        let newTapDesc = CATapDescription(stereoMixdownOfProcesses: [app.objectID])
        newTapDesc.uuid = UUID()
        newTapDesc.muteBehavior = .mutedWhenTapped

        var newTapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(newTapDesc, &newTapID)
        guard err == noErr else {
            throw CrossfadeError.tapCreationFailed(err)
        }

        let description = buildAggregateDescription(
            outputUIDs: outputUIDs,
            tapUUID: newTapDesc.uuid,
            name: "diodiooodio-\(app.id)"
        )

        var newAggregateID: AudioObjectID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID)
        guard err == noErr else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw CrossfadeError.aggregateCreationFailed(err)
        }

        guard newAggregateID.waitUntilReady(timeout: 2.0) else {
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw CrossfadeError.deviceNotReady
        }

        var newDeviceProcID: AudioDeviceIOProcID?
        err = AudioDeviceCreateIOProcIDWithBlock(&newDeviceProcID, newAggregateID, queue) { [weak self] _, inInputData, _, outOutputData, _ in
            guard let self else { return }
            self.processAudio(inInputData, to: outOutputData)
        }
        guard err == noErr else {
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw CrossfadeError.tapCreationFailed(err)
        }

        err = AudioDeviceStart(newAggregateID, newDeviceProcID)
        guard err == noErr else {
            if let procID = newDeviceProcID {
                AudioDeviceDestroyIOProcID(newAggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw CrossfadeError.tapCreationFailed(err)
        }

        CrossfadeOrchestrator.destroyTap(aggregateID: aggregateDeviceID, deviceProcID: deviceProcID, tapID: processTapID)

        processTapID = newTapID
        tapDescription = newTapDesc
        aggregateDeviceID = newAggregateID
        deviceProcID = newDeviceProcID
        targetDeviceUIDs = outputUIDs
        currentDeviceUIDs = outputUIDs

        if let deviceSampleRate = try? aggregateDeviceID.readNominalSampleRate() {
            rampCoefficient = 1 - exp(-1 / (Float(deviceSampleRate) * 0.030))
            eqProcessor?.updateSampleRate(deviceSampleRate)
        }
    }

    private func cleanupPartialActivation() {
        if let procID = deviceProcID {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            deviceProcID = nil
        }
        if aggregateDeviceID.isValid {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }
        if processTapID.isValid {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = .unknown
        }
    }

    // MARK: - process 오디오

    /// 처리 오디오 동작을 처리합니다.
    private func processAudio(_ inputBufferList: UnsafePointer<AudioBufferList>, to outputBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputBufferList)
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBufferList))

        if _forceSilence {
            for outputBuffer in outputBuffers {
                guard let outputData = outputBuffer.mData else { continue }
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
            }
            return
        }

        var maxPeak: Float = 0.0
        for inputBuffer in inputBuffers {
            guard let inputData = inputBuffer.mData else { continue }
            let inputSamples = inputData.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            for i in stride(from: 0, to: sampleCount, by: 2) {
                let absSample = abs(inputSamples[i])
                if absSample > maxPeak {
                    maxPeak = absSample
                }
            }
        }
        let rawPeak = min(maxPeak, 1.0)
        _peakLevel = _peakLevel + levelSmoothingFactor * (rawPeak - _peakLevel)

        if _isMuted {
            for outputBuffer in outputBuffers {
                guard let outputData = outputBuffer.mData else { continue }
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
            }
            return
        }

        let targetVol = _volume
        var currentVol = _primaryCurrentVolume

        let crossfadeMultiplier: Float
        if _isCrossfading {
            crossfadeMultiplier = cos(_crossfadeProgress * .pi / 2.0)
        } else if _crossfadeProgress >= 1.0 {
            crossfadeMultiplier = 0.0
        } else {
            crossfadeMultiplier = 1.0
        }

        let inputBufferCount = inputBuffers.count
        let outputBufferCount = outputBuffers.count

        for outputIndex in 0..<outputBufferCount {
            let outputBuffer = outputBuffers[outputIndex]
            guard let outputData = outputBuffer.mData else { continue }

            let inputIndex: Int
            if inputBufferCount > outputBufferCount {
                inputIndex = inputBufferCount - outputBufferCount + outputIndex
            } else {
                inputIndex = outputIndex
            }

            guard inputIndex < inputBufferCount else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputBuffer = inputBuffers[inputIndex]
            guard let inputData = inputBuffer.mData else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputSamples = inputData.assumingMemoryBound(to: Float.self)
            let outputSamples = outputData.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size

            for i in 0..<sampleCount {
                currentVol += (targetVol - currentVol) * rampCoefficient
                let effectiveCompensation: Float = _isCrossfading ? 1.0 : _deviceVolumeCompensation
                var sample = inputSamples[i] * currentVol * crossfadeMultiplier * effectiveCompensation
                if targetVol > 1.0 {
                    sample = softLimit(sample)
                }
                outputSamples[i] = sample
            }

            if let eqProcessor = eqProcessor, !_isCrossfading {
                let channels = Int(inputBuffer.mNumberChannels)
                let frameCount = channels > 1 ? sampleCount / channels : sampleCount
                eqProcessor.process(input: outputSamples, output: outputSamples, frameCount: frameCount)
            }
        }

        _primaryCurrentVolume = currentVol
    }

    /// 처리 오디오 보조 동작을 처리합니다.
    private func processAudioSecondary(_ inputBufferList: UnsafePointer<AudioBufferList>, to outputBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputBufferList)
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBufferList))

        var maxPeak: Float = 0.0
        var totalSamplesThisBuffer: Int = 0
        for inputBuffer in inputBuffers {
            guard let inputData = inputBuffer.mData else { continue }
            let inputSamples = inputData.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            if totalSamplesThisBuffer == 0 {
                totalSamplesThisBuffer = sampleCount / 2
            }
            for i in stride(from: 0, to: sampleCount, by: 2) {
                let absSample = abs(inputSamples[i])
                if absSample > maxPeak {
                    maxPeak = absSample
                }
            }
        }
        let rawPeak = min(maxPeak, 1.0)
        _peakLevel = _peakLevel + levelSmoothingFactor * (rawPeak - _peakLevel)

        _secondarySamplesProcessed += totalSamplesThisBuffer
        if _isCrossfading {
            _secondarySampleCount += Int64(totalSamplesThisBuffer)
        }

        if _isMuted {
            for outputBuffer in outputBuffers {
                guard let outputData = outputBuffer.mData else { continue }
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
            }
            return
        }

        let targetVol = _volume
        var currentVol = _secondaryCurrentVolume

        var crossfadeMultiplier: Float = 1.0
        if _isCrossfading {
            let progress = min(1.0, Float(_secondarySampleCount) / Float(max(1, _crossfadeTotalSamples)))
            _crossfadeProgress = progress
            crossfadeMultiplier = sin(progress * .pi / 2.0)
        }

        let inputBufferCount = inputBuffers.count
        let outputBufferCount = outputBuffers.count

        for outputIndex in 0..<outputBufferCount {
            let outputBuffer = outputBuffers[outputIndex]
            guard let outputData = outputBuffer.mData else { continue }

            let inputIndex: Int
            if inputBufferCount > outputBufferCount {
                inputIndex = inputBufferCount - outputBufferCount + outputIndex
            } else {
                inputIndex = outputIndex
            }

            guard inputIndex < inputBufferCount else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputBuffer = inputBuffers[inputIndex]
            guard let inputData = inputBuffer.mData else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputSamples = inputData.assumingMemoryBound(to: Float.self)
            let outputSamples = outputData.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size

            for i in 0..<sampleCount {
                currentVol += (targetVol - currentVol) * secondaryRampCoefficient
                var sample = inputSamples[i] * currentVol * crossfadeMultiplier * _deviceVolumeCompensation
                if targetVol > 1.0 {
                    sample = softLimit(sample)
                }
                outputSamples[i] = sample
            }

            if let eqProcessor = eqProcessor, !_isCrossfading {
                let channels = Int(inputBuffer.mNumberChannels)
                let frameCount = channels > 1 ? sampleCount / channels : sampleCount
                eqProcessor.process(input: outputSamples, output: outputSamples, frameCount: frameCount)
            }
        }

        _secondaryCurrentVolume = currentVol
    }

    /// soft limit 동작을 처리합니다.
    @inline(__always)
    private func softLimit(_ sample: Float) -> Float {
        let threshold: Float = 0.8
        let ceiling: Float = 1.0

        let absSample = abs(sample)
        if absSample <= threshold {
            return sample
        }

        let overshoot = absSample - threshold
        let headroom = ceiling - threshold  // 0.2
        let compressed = threshold + headroom * (overshoot / (overshoot + headroom))

        return sample >= 0 ? compressed : -compressed
    }
}
