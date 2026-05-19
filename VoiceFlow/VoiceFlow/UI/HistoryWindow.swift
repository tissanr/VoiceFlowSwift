import SwiftUI

/// Phase 6 — Verlauf & Analytik
struct HistoryView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Picker("", selection: $selectedTab) {
                Text("Verlauf").tag(0)
                Text("Analyse").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if selectedTab == 0 {
                historyList
            } else {
                analyticsView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear(perform: loadEntries)
    }
    
    private var historyList: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(entry.words) Wörter")
                        .font(.caption2)
                }
                Text(entry.text)
                    .font(.body)
                    .lineLimit(3)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var analyticsView: some View {
        VStack(spacing: 20) {
            HStack(spacing: 40) {
                statCard(title: "Wörter gesamt", value: "\(entries.reduce(0) { $0 + $1.words })")
                statCard(title: "Sitzungen", value: "\(entries.count)")
            }
            
            Text("Aktivität (letzte 30 Tage)")
                .font(.headline)
            
            // Heatmap-Platzhalter
            HStack(spacing: 4) {
                ForEach(0..<30) { _ in
                    Rectangle()
                        .fill(Color.blue.opacity(Double.random(in: 0.1...1.0)))
                        .frame(width: 15, height: 15)
                        .cornerRadius(2)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func statCard(title: String, value: String) -> some View {
        VStack {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title).bold()
        }
    }
    
    private func loadEntries() {
        // TODO: word_log.jsonl laden
        self.entries = [
            HistoryEntry(text: "Das ist ein Beispiel-Diktat.", date: Date(), words: 5),
            HistoryEntry(text: "VoiceFlow funktioniert jetzt nativ in Swift.", date: Date().addingTimeInterval(-86400), words: 7)
        ]
    }
}

struct HistoryEntry: Identifiable {
    let id = UUID()
    let text: String
    let date: Date
    let words: Int
}
