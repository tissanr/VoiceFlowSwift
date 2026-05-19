import SwiftUI

/// Phase 6 — Verlauf & Analytik
struct HistoryView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var selectedTab = 0
    @State private var heatValues: [Double] = (0..<30).map { _ in Double.random(in: 0.1...1.0) }

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
        .task { await loadEntries() }
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
            
            HStack(spacing: 4) {
                ForEach(0..<30, id: \.self) { i in
                    Rectangle()
                        .fill(Color.blue.opacity(heatValues[i]))
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
    
    private func loadEntries() async {
        let logEntries = await WordLogger.shared.readEntries(limit: 200)
        self.entries = logEntries.map { e in
            HistoryEntry(text: e.text, date: e.date ?? Date(), words: e.words)
        }
    }
}

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let date: Date
    let words: Int

    init(text: String, date: Date, words: Int) {
        self.id = UUID()
        self.text = text
        self.date = date
        self.words = words
    }
}
