@preconcurrency import AVFoundation
import Accelerate
import CoreAudio

typealias AudioSamples = [Float]

// Phase 2 — Microphone recording via AVFoundation
// AVAudioEngine is started only on the first recording.
actor AudioRecorder {
    private let engine = AVAudioEngine()
    private let captureState = AudioCaptureState()
    private var converter: AVAudioConverter?
    private var isPrepared = false
    private var isRecording = false

    var currentRMS: Float { captureState.currentRMS }

    // Sample rate and format expected by WhisperKit
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Lifecycle

    /// Call once before the first recording.
    func prepare() async throws {
        guard !isPrepared else { return }

        try await requestMicrophonePermission()
        isPrepared = true
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
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }

        if inputFormat.sampleRate != targetFormat.sampleRate || inputFormat.channelCount != targetFormat.channelCount {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        } else {
            converter = nil
        }

        captureState.reset(reservingCapacity: 16_000 * 120)
        let converter = converter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            self?.captureState.accumulate(
                pcmBuffer,
                inputFormat: inputFormat,
                targetFormat: targetFormat,
                converter: converter
            )
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                inputNode.removeTap(onBus: 0)
                throw AudioRecorderError.engineStartFailed(error)
            }
        }
        isRecording = true
    }

    func stop() -> AudioSamples {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        return captureState.samples()
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
    }

    // MARK: - Permission

    private func requestMicrophonePermission() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted {
            throw AudioRecorderError.microphoneAccessDenied
        }
    }
}

private final class AudioCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AudioSamples = []
    private var rms: Float = 0.0

    var currentRMS: Float {
        lock.lock()
        defer { lock.unlock() }
        return rms
    }

    func reset(reservingCapacity capacity: Int) {
        lock.lock()
        buffer = []
        buffer.reserveCapacity(capacity)
        rms = 0.0
        lock.unlock()
    }

    func samples() -> AudioSamples {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func accumulate(
        _ inputBuffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        converter: AVAudioConverter?
    ) {
        let converted: AVAudioPCMBuffer

        if let converter {
            let frameCapacity = AVAudioFrameCount(
                Double(inputBuffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate + 1
            )
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }
            var error: NSError?
            var inputConsumed = false
            converter.convert(to: outBuf, error: &error) { _, outStatus in
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

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(count))

        lock.lock()
        buffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
        self.rms = rms
        lock.unlock()
    }
}

enum AudioRecorderError: Error {
    case microphoneAccessDenied
    case noInputDevice
    case engineStartFailed(Error)
    case deviceSetFailed(OSStatus)
}

extension AudioRecorderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access was not granted."
        case .noInputDevice:
            return "No valid input device found."
        case .engineStartFailed(let error):
            return "Audio engine could not be started: \(error.localizedDescription)"
        case .deviceSetFailed(let status):
            return "Input device could not be set: \(status)"
        }
    }
}
