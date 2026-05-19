import Foundation
import AppKit

/// Phase 6 — Orchestriert den gesamten Flow (Audio -> Whisper -> LLM -> Delivery)
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
    
    /// Startet den Workflow (bei Hotkey Down)
    func beginRecording() async {
        guard state.status == .idle else { return }
        
        capturedContext = CursorContext.get()
        recordingStarted = Date()
        
        // 2. Aufnahme starten
        do {
            try await recorder.prepare()
            try await recorder.start()
            state.status = .recording
            
            // RMS-Updates für das Overlay
            startRMSUpdates()
        } catch {
            state.status = .error("Mikrofon konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }
    
    /// Beendet den Workflow (bei Hotkey Up)
    func endRecording() async {
        guard state.status == .recording else { return }
        
        state.status = .stopping
        
        do {
            // 1. Audio abholen
            let audio = await recorder.stop()
            state.status = .processing
            
            // 2. Transkribieren
            let vocab = await vocabLearner.vocabulary
            let transcription = try await transcriber.transcribe(
                audio: audio,
                language: state.settings.language,
                vocabulary: vocab,
                profile: state.settings.transcriptionProfile
            )
            
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
            
            // 4. Lernen (Background)
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
            
            // 6. Ausliefern
            state.lastTranscription = processedText
            let result = await TextDelivery.deliver(
                text: processedText,
                context: capturedContext,
                outputMode: state.settings.textOutputMode
            )
            
            switch result {
            case .success:
                state.status = .idle
            case .failure(let error):
                state.status = .error(error)
            }
            
        } catch {
            state.status = .error("Fehler: \(error.localizedDescription)")
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
                state.status = .error("Warmup fehlgeschlagen: \(error.localizedDescription)")
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
            state.status = .error("Modell-Download fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
