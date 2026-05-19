import Foundation
import Combine

/// Phase 6 — App-weiten Status verwalten
enum AppStatus: Equatable {
    case idle
    case recording
    case stopping
    case processing
    case initializing(progress: Double)
    case downloading(model: String, progress: Double)
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var settings: AppSettings = AppSettings.load()
    @Published var lastTranscription: String?
    @Published var audioRMS: Float = 0
    
    let levelMapper = OverlayLevelMapper()
    var cancellables = Set<AnyCancellable>()
    
    // singleton für einfachen Zugriff
    static let shared = AppState()
    
    private init() {}
    
    func updateSettings() {
        self.settings = AppSettings.load()
    }
}
