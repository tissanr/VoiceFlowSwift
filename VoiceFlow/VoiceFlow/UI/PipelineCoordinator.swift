import Accelerate
import Foundation
import AppKit

/// Phase 6 — Orchestrates the full pipeline (Audio -> Whisper -> LLM -> Delivery)
@MainActor
final class PipelineCoordinator {
    
    private let state: AppState
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let llmProcessor = LLMPostProcessor()
    private let vocabLearner = VocabLearner()
    private let wordLogger = WordLogger.shared
    
    private var capturedContext: String?
    private var recordingStarted: Date?
    
    init(state: AppState) {
        self.state = state
    }
    
    /// Starts the pipeline (on hotkey down)
    func beginRecording() async {
        guard state.status == .idle else { return }
        
        capturedContext = CursorContext.get()
        recordingStarted = Date()
        
        // 2. Start recording
        do {
            try await recorder.prepare()
            try await recorder.start()
            state.status = .recording
            
            // RMS updates for the overlay
            startRMSUpdates()
        } catch {
            state.status = .error("Microphone could not be started: \(error.localizedDescription)")
        }
    }
    
    /// Ends the pipeline (on hotkey up)
    func endRecording() async {
        guard state.status == .recording else { return }
        
        state.status = .stopping
        
        do {
            // 1. Fetch audio
            let audio = await recorder.stop()
            var rmsVal: Float = 0; if !audio.isEmpty { vDSP_rmsqv(audio, 1, &rmsVal, vDSP_Length(audio.count)) }
            print("[Pipeline] audio samples: \(audio.count), RMS: \(String(format: "%.4f", rmsVal))")
            state.status = .processing

            // 2. Transcribe
            let vocab = await vocabLearner.vocabulary
            let transcription = try await transcriber.transcribe(
                audio: audio,
                language: state.settings.language,
                vocabulary: vocab,
                profile: state.settings.transcriptionProfile
            )
            print("[Pipeline] transcription: '\(transcription.text)' filtered=\(transcription.wasFiltered) rms=\(String(format: "%.4f", transcription.inputRMS))")

            if transcription.text.isEmpty {
                state.status = .idle
                return
            }

            // 3. LLM Enhancement (optional)
            let capitalized = CursorContext.shouldCapitalize(context: capturedContext)
            let processedText = await llmProcessor.process(
                text: transcription.text,
                settings: state.settings,
                capitalize: capitalized,
                vocabulary: vocab
            )

            // 4. Learn (background)
            if processedText != transcription.text {
                await vocabLearner.learn(original: transcription.text, corrected: processedText)
            }

            // 5. Logging
            let duration = recordingStarted.map { Date().timeIntervalSince($0) }
            await wordLogger.log(
                text: processedText,
                durationS: duration,
                correctionRatio: nil
            )

            // 6. Deliver
            print("[Pipeline] delivering: '\(processedText)' via \(state.settings.textOutputMode) AX=\(TextInjector.canControlUI)")
            state.lastTranscription = processedText
            let result = await TextDelivery.deliver(
                text: processedText,
                context: capturedContext,
                outputMode: state.settings.textOutputMode
            )
            print("[Pipeline] result: \(result)")

            switch result {
            case .success:
                state.status = .idle
            case .failure(let error):
                state.status = .error(error)
            }

        } catch {
            print("[Pipeline] error: \(error)")
            state.status = .error("Error: \(error.localizedDescription)")
        }
    }
    
    private func startRMSUpdates() {
        Task {
            while state.status == .recording {
                state.audioRMS = await recorder.currentRMS
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }
    
    func warmup() async {
        let variant = ModelManager.defaultWhisperVariant
        if ModelManager.isCached(modelName: variant) {
            state.status = .initializing(progress: 0.1)
            do {
                _ = try await transcriber.warmup()
                state.status = .idle
            } catch {
                state.status = .error("Warmup failed: \(error.localizedDescription)")
            }
        } else {
            await downloadAndWarmup(variant: variant)
        }
    }

    private func downloadAndWarmup(variant: String) async {
        let downloader = ModelDownloader()
        state.status = .downloading(model: variant, progress: 0)
        do {
            _ = try await downloader.downloadWhisperModel(variant: variant) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.state.status = .downloading(model: variant, progress: progress)
                }
            }
            state.status = .initializing(progress: 0.9)
            _ = try? await transcriber.warmup()
            state.status = .idle
        } catch {
            state.status = .error("Model download failed: \(error.localizedDescription)")
        }
    }
}
