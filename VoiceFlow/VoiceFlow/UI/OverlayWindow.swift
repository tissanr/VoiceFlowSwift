import SwiftUI
import AppKit

/// Phase 6 — Schwebendes Overlay-Panel
final class OverlayWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.hasShadow = true
        
        centerOnScreen()
    }
    
    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - frame.width / 2
        let y = screen.frame.minY + 100
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct OverlayView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        Group {
            switch state.status {
            case .recording:
                recordingView
            case .processing, .stopping:
                processingView
            case .initializing(let progress):
                progressView(title: "Initialisierung...", progress: progress)
            case .downloading(let model, let progress):
                progressView(title: "Download: \(model)", progress: progress)
            case .error(let msg):
                errorView(msg)
            default:
                EmptyView()
            }
        }
        .padding()
        .background(Color(white: 0.1).opacity(0.9))
        .clipShape(Capsule())
        .foregroundColor(.white)
    }
    
    private var recordingView: some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
            WaveformView(state: state)
        }
    }
    
    private var processingView: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("Verarbeitung...")
        }
    }
    
    private func progressView(title: String, progress: Double) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption)
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .frame(width: 200)
    }
    
    private func errorView(_ msg: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text(msg).font(.caption)
        }
    }
}

struct WaveformView: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 10
            HStack(spacing: 2) {
                ForEach(0..<9) { i in
                    let height = state.levelMapper.barHeights(rms: state.audioRMS, phase: phase)[i]
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.95, green: 0.4, blue: 0.48)) // Rose color
                        .frame(width: 3, height: CGFloat(height * 20) + 4)
                }
            }
        }
    }
}
