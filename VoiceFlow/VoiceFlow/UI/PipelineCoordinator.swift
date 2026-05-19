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
    
    // Wir speichern den Cursor-Kontext VOR der Aufnahme
    private var capturedContext: String?
    
    init(state: AppState = .shared) {
        self.state = state
    }
    
    /// Startet den Workflow (bei Hotkey Down)
    func beginRecording() async {
        guard state.status == .idle else { return }
        
        // 1. Kontext vor der Aufnahme erfassen
        capturedContext = CursorContext.get()
        
        // 2. Aufnahme starten
        do {
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
            let audio = try await recorder.stop()
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
            await wordLogger.log(
                text: processedText,
                durationS: 0, // TODO: Zeit messen
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
        state.status = .initializing(progress: 0.1)
        do {
            _ = try await transcriber.warmup()
            state.status = .idle
        } catch {
            state.status = .error("Warmup fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
