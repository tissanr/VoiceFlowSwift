@preconcurrency import AVFoundation
import Accelerate
import CoreAudio

typealias AudioSamples = [Float]

// Phase 2 — Mikrofon-Aufnahme via AVFoundation
// AVAudioEngine wird beim App-Start warm gehalten; nur der Tap wird ein-/ausgeschaltet.
actor AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var buffer: AudioSamples = []
    private var isRecording = false

    private(set) var currentRMS: Float = 0.0

    // Sample-Rate und Format erwartet von WhisperKit
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Lifecycle

    /// Einmalig beim App-Start aufrufen — hält Engine warm.
    func prepare() async throws {
        try await requestMicrophonePermission()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        if inputFormat.sampleRate != 16_000 || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat)
        }

        // Dummy-Tap damit die Engine gestartet werden kann
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { _, _ in }
        try engine.start()
        inputNode.removeTap(onBus: 0)
    }

    // MARK: - Recording

    func start(deviceID: AudioDeviceID? = nil) throws {
        guard !isRecording else { return }

        if let deviceID {
            try setInputDevice(deviceID)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = Self.targetFormat

        buffer = []
        buffer.reserveCapacity(16_000 * 120)  // 2 Minuten max

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            Task { await self?.accumulate(pcmBuffer, inputFormat: inputFormat, targetFormat: targetFormat) }
        }

        if !engine.isRunning {
            try engine.start()
        }
        isRecording = true
    }

    func stop() -> AudioSamples {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        return buffer
    }

    // MARK: - Internal

    private func accumulate(
        _ inputBuffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) {
        let converted: AVAudioPCMBuffer

        if let conv = converter {
            let frameCapacity = AVAudioFrameCount(
                Double(inputBuffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate + 1
            )
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }
            var error: NSError?
            var inputConsumed = false
            conv.convert(to: outBuf, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
            guard error == nil else { return }
            converted = outBuf
        } else {
            converted = inputBuffer
        }

        guard let channelData = converted.floatChannelData?[0] else { return }
        let count = Int(converted.frameLength)
        buffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(count))
        currentRMS = rms
    }

    // MARK: - Device selection

    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        var id = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &id
        )
        if status != noErr {
            throw AudioRecorderError.deviceSetFailed(status)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.reset()
        try engine.start()
    }

    // MARK: - Permission

    private func requestMicrophonePermission() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted {
            throw AudioRecorderError.microphoneAccessDenied
        }
    }
}

enum AudioRecorderError: Error {
    case microphoneAccessDenied
    case deviceSetFailed(OSStatus)
}
